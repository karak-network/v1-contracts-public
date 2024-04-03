// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {PausableUpgradeable} from "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "solady/src/utils/UUPSUpgradeable.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";

import "./entities/Withdraw.sol";
import "./entities/DelegationSupervisorLib.sol";
import "./entities/Staker.sol";

import {Constants} from "./interfaces/Constants.sol";
import {IVault} from "./interfaces/IVault.sol";
import "./interfaces/IDelegationSupervisor.sol";
import "./interfaces/Events.sol";

contract DelegationSupervisor is
    IDelegationSupervisor,
    Initializable,
    OwnableRoles,
    ReentrancyGuard,
    PausableUpgradeable,
    EIP712Upgradeable
{
    using DelegationSupervisorLib for DelegationSupervisorLib.Storage;
    using Withdraw for Withdraw.QueuedWithdrawal;
    using Withdraw for Withdraw.WithdrawRequest[];
    using Withdraw for Withdraw.WithdrawRequest;

    // keccak256(abi.encode(uint256(keccak256("delegationsupervisor.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_SLOT = 0xb0b02f0ecb09a6e798b0f902b13ac86c2c157da412a7f4294fa1ae79336f7700;

    /* ========== MUTATIVE FUNCTIONS ========== */

    constructor() {
        _disableInitializers();
    }

    function initialize(address vaultSupervisor, uint256 minWithdrawDelay, address manager) external initializer {
        _initializeOwner(msg.sender);
        __Pausable_init();
        __EIP712_init("Karak_Delegation_Sup", "v1");

        _grantRoles(manager, Constants.MANAGER_ROLE);

        DelegationSupervisorLib.Storage storage self = _self();
        self.initOrUpdate(vaultSupervisor, minWithdrawDelay);
    }

    function updateMinWithdrawDelay(uint256 delay) external onlyRolesOrOwner(Constants.MANAGER_ROLE) {
        DelegationSupervisorLib.Storage storage self = _self();
        self.updateMinWithdrawDelay(delay);
    }

    function startWithdraw(Withdraw.WithdrawRequest[] calldata withdrawalRequests)
        external
        nonReentrant
        whenNotPaused
        returns (bytes32[] memory withdrawalRoots, Withdraw.QueuedWithdrawal[] memory withdrawConfigs)
    {
        if (withdrawalRequests.length == 0) revert InvalidInput();
        DelegationSupervisorLib.Storage storage self = _self();
        withdrawalRoots = new bytes32[](withdrawalRequests.length);
        withdrawConfigs = new Withdraw.QueuedWithdrawal[](withdrawalRequests.length);
        address operator = self.stakers[msg.sender].delegatee;

        for (uint256 i = 0; i < withdrawalRequests.length; i++) {
            withdrawalRequests[i].validate();
            // Remove shares from staker's strategies and place strategies/shares in queue.
            (withdrawalRoots[i], withdrawConfigs[i]) = removeSharesAndStartWithdrawal({
                staker: msg.sender,
                operator: operator,
                withdrawer: withdrawalRequests[i].withdrawer,
                vaults: withdrawalRequests[i].vaults,
                shares: withdrawalRequests[i].shares
            });
        }
    }

    function finishWithdraw(Withdraw.QueuedWithdrawal[] calldata startedWithdrawals)
        external
        nonReentrant
        whenNotPaused
    {
        for (uint256 i = 0; i < startedWithdrawals.length; ++i) {
            DelegationSupervisorLib.Storage storage self = _self();
            startedWithdrawals[i].finishStartedWithdrawal(self);
        }
    }

    function pause(bool toPause) external onlyRolesOrOwner(Constants.MANAGER_ROLE) {
        if (toPause) _pause();
        else _unpause();
    }

    /* ========== VIEW FUNCTIONS ========== */

    function withdrawalDelay() external view override returns (uint256) {
        DelegationSupervisorLib.Storage storage self = _self();
        return self.withdrawalDelay;
    }

    function fetchQueuedWithdrawals(address staker)
        external
        view
        returns (Withdraw.QueuedWithdrawal[] memory queuedWithdrawals)
    {
        DelegationSupervisorLib.Storage storage self = _self();
        queuedWithdrawals = self.stakers[staker].queuedWithdrawals;
    }

    function isWithdrawPending(Withdraw.QueuedWithdrawal calldata withdrawal) external view returns (bool) {
        DelegationSupervisorLib.Storage storage self = _self();
        return self.pendingWithdrawals[withdrawal.calculateWithdrawalRoot()];
    }
    /* ========== MODIFIERS ========== */

    modifier onlyVaultSupervisor() {
        DelegationSupervisorLib.Storage storage self = _self();
        if (msg.sender != address(self.vaultSupervisor)) {
            revert NotVaultSupervisor();
        }
        _;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _self() private pure returns (DelegationSupervisorLib.Storage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    /**
     * @notice
     *     @param staker The staker who is withdrawing. NOTE assumes this is validated already
     */
    function removeSharesAndStartWithdrawal(
        address staker,
        address operator,
        address withdrawer,
        IVault[] memory vaults,
        uint256[] memory shares
    ) internal returns (bytes32 withdrawalRoot, Withdraw.QueuedWithdrawal memory withdrawal) {
        DelegationSupervisorLib.Storage storage self = _self();
        for (uint256 i = 0; i < vaults.length; i++) {
            if (shares[i] == 0) revert ZeroShares();
            //_decreaseOperatorShares(operator, vaults[i], shares[i]);
            self.vaultSupervisor.removeShares(staker, vaults[i], shares[i]);
            emit StartedWithdrawal(address(vaults[i]), staker, operator, withdrawer, shares[i]);
        }
        uint256 nonce = self.stakers[staker].totalWithdrawsQueued;
        self.stakers[staker].totalWithdrawsQueued++;
        withdrawal = Withdraw.QueuedWithdrawal({
            staker: staker,
            delegatedTo: operator,
            nonce: nonce,
            start: uint256(block.timestamp),
            request: Withdraw.WithdrawRequest({vaults: vaults, shares: shares, withdrawer: withdrawer})
        });
        withdrawalRoot = withdrawal.calculateWithdrawalRoot();
        self.pendingWithdrawals[withdrawalRoot] = true;
        self.stakers[msg.sender].queuedWithdrawals.push(withdrawal);
    }
}
