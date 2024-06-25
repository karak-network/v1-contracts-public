// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {EIP712Upgradeable} from "@openzeppelin-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "solady/src/utils/UUPSUpgradeable.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

import {IVault} from "./interfaces/IVault.sol";
import {ISwapper} from "./interfaces/ISwapper.sol";

import "./interfaces/IVaultSupervisor.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IDelegationSupervisor.sol";
import "./interfaces/Constants.sol";
import "./interfaces/Errors.sol";
import "./interfaces/Events.sol";
import "./interfaces/ILimiter.sol";
import "./entities/VaultSupervisorLib.sol";

contract VaultSupervisor is
    Initializable,
    OwnableRoles,
    ReentrancyGuard,
    PausableUpgradeable,
    UUPSUpgradeable,
    IVaultSupervisor,
    IBeacon
{
    using VaultSupervisorLib for VaultSupervisorLib.Storage;

    // keccak256(abi.encode(uint256(keccak256("vaultsupervisor.storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant STORAGE_SLOT = 0xa850f9cb190d34eca968aeee8c951b4765e62744d7c13847a3ad392ad8649100;

    /* ========== MUTATIVE FUNCTIONS ========== */

    constructor() {
        _disableInitializers();
    }

    function initialize(address _delegationSupervisor, address _vaultImpl, ILimiter _limiter, address _manager)
        external
        initializer
    {
        _initializeOwner(msg.sender);
        __Pausable_init();

        _grantRoles(_manager, Constants.MANAGER_ROLE);

        VaultSupervisorLib.Storage storage self = _self();
        self.initOrUpdate(_delegationSupervisor, _vaultImpl, _limiter);
    }

    function deposit(IVault vault, uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        return depositInternal(msg.sender, msg.sender, vault, amount, minSharesOut);
    }

    function depositAndGimmie(IVault vault, uint256 amount, uint256 minSharesOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        shares = depositInternal(msg.sender, msg.sender, vault, amount, minSharesOut);
        gimmieSharesInternal(vault, shares);
    }

    function depositWithSignature(
        IVault vault,
        address user,
        uint256 value,
        uint256 minSharesOut,
        uint256 deadline,
        Signature calldata permit,
        Signature calldata vaultAllowance
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        VaultSupervisorLib.Storage storage self = _self();
        VaultSupervisorLib.verifySignatures(
            vault, user, value, minSharesOut, deadline, permit, vaultAllowance, self.userNonce[user]
        );
        self.userNonce[user]++;
        return depositInternal(user, user, vault, value, minSharesOut);
    }

    function redeemShares(address staker, IVault vault, uint256 shares)
        external
        onlyDelegationSupervisor
        onlyChildVault(vault)
        nonReentrant
    {
        redeemSharesInternal(staker, vault, shares);
    }

    function removeShares(address staker, IVault vault, uint256 shares)
        external
        onlyDelegationSupervisor
        onlyChildVault(vault)
        nonReentrant
    {
        removeSharesInternal(staker, vault, shares);
    }

    function pause(bool toPause) external onlyRolesOrOwner(Constants.MANAGER_ROLE) {
        if (toPause) _pause();
        else _unpause();
    }

    function deployVault(IERC20 depositToken, string memory name, string memory symbol, IVault.AssetType assetType)
        external
        onlyRolesOrOwner(Constants.MANAGER_ROLE)
        returns (IVault)
    {
        VaultSupervisorLib.Storage storage self = _self();
        IVault vault =
            cloneVault(abi.encodeCall(IVault.initialize, (address(this), depositToken, name, symbol, assetType)));
        self.vaults.push(vault);
        // Optimization: Set to constant so we can see if a vault exists and was made by us in O(1) time
        self.vaultToImplMap[address(vault)] = Constants.DEFAULT_VAULT_IMPLEMENTATION_FLAG;
        emit NewVault(address(vault));
        return vault;
    }

    function changeImplementation(address newVaultImpl) external onlyOwner {
        if (newVaultImpl == address(0)) revert ZeroAddress();
        VaultSupervisorLib.Storage storage self = _self();
        self.vaultImpl = newVaultImpl;
        emit UpgradedAllVaults(newVaultImpl);
    }

    function changeImplementationForVault(address vault, address newVaultImpl) external onlyOwner {
        // Don't let the implementation ever be changed to 0 after it's created.
        // It's either DEFAULT_VAULT_IMPLEMENTATION_FLAG or a valid address
        if (newVaultImpl == address(0)) revert ZeroAddress();

        VaultSupervisorLib.Storage storage self = _self();

        // Don't let the admin change the implementation from address(0) to something else
        // bypassing the deployVault flow
        if (self.vaultToImplMap[vault] == address(0)) revert VaultNotAChildVault();

        self.vaultToImplMap[vault] = newVaultImpl;
        emit UpgradedVault(newVaultImpl, vault);
    }

    /// @dev Allow for it to be set to address(0)
    /// in the future to disable the global limit
    function setLimiter(ILimiter limiter) external onlyRolesOrOwner(Constants.MANAGER_ROLE) {
        VaultSupervisorLib.Storage storage self = _self();
        self.limiter = limiter;
    }

    function runAdminOperation(IVault vault, bytes calldata fn)
        external
        onlyRolesOrOwner(Constants.MANAGER_ROLE)
        nonReentrant
        returns (bytes memory)
    {
        bytes4 incomingFnSelector = bytes4(fn);
        bool isValidAdminFunction = (
            incomingFnSelector == IVault.setLimit.selector || incomingFnSelector == IVault.transferOwnership.selector
                || incomingFnSelector == IVault.pause.selector
        );
        if (!isValidAdminFunction) {
            revert InvalidVaultAdminFunction();
        }

        // Only the owner can transferOwnership of the vault
        if (incomingFnSelector == IVault.transferOwnership.selector) {
            _checkOwner();
        }

        (bool success, bytes memory result) = address(vault).call(fn);

        if (!success) {
            // Load revert reason into memory and revert
            // with it because we can't revert with bytes
            // from https://ethereum.stackexchange.com/a/114140
            assembly {
                revert(add(result, 32), result)
            }
        }

        return result;
    }

    function registerSwapperForRoutes(IERC20[] calldata inputAsset, IERC20[] calldata outputAsset, ISwapper swapper)
        external
        onlyOwner
    {
        uint256 routeCount = inputAsset.length;
        if (routeCount != outputAsset.length) revert InvalidSwapperRouteLength();

        for (uint256 i = 0; i < routeCount; i++) {
            IERC20 inputAsset = inputAsset[i];
            IERC20 outputAsset = outputAsset[i];

            if (!swapper.canSwap(inputAsset, outputAsset)) {
                revert InvalidSwapper();
            }

            _self().inputToOutputToSwapper[inputAsset][outputAsset] = swapper;
        }
    }

    function vaultSwap(
        IVault vault,
        IVault.SwapAssetParams calldata params,
        uint256 minNewAssetAmount,
        bytes calldata swapperParams
    ) external nonReentrant onlyRolesOrOwner(Constants.MANAGER_ROLE) onlyChildVault(vault) {
        ISwapper swapper = _self().inputToOutputToSwapper[IERC20(vault.asset())][params.newDepositToken];
        if (address(swapper) == address(0)) {
            revert InvalidSwapper();
        }

        vault.swapAsset(swapper, params, minNewAssetAmount, swapperParams);
    }

    function migrate(
        IVault oldVault,
        IVault newVault,
        uint256 oldShares,
        uint256 minNewShares,
        bytes calldata swapperOtherParams
    ) external nonReentrant onlyChildVault(oldVault) onlyChildVault(newVault) whenNotPaused {
        IERC20 oldAsset = IERC20(oldVault.asset());
        IERC20 newAsset = IERC20(newVault.asset());

        ISwapper swapper = _self().inputToOutputToSwapper[oldAsset][newAsset];
        if (address(swapper) == address(0)) {
            revert InvalidSwapper();
        }

        // NOTE: convertToAssets does not take fees into account.
        //       But we don't need to take fees into account here since this code path won't be used for any vaults that have this behavior.
        uint256 oldAssetsToSwap = oldVault.convertToAssets(oldShares);
        uint256 minNewAssets = newVault.convertToAssets(minNewShares);

        ISwapper.SwapParams memory swapParams = ISwapper.SwapParams({
            inputAsset: oldAsset,
            outputAsset: newAsset,
            inputAmount: oldAssetsToSwap,
            minOutputAmount: minNewAssets
        });

        uint256 oldAssetsBeforeRedeem = oldAsset.balanceOf(address(this));
        removeSharesInternal(msg.sender, oldVault, oldShares);
        redeemSharesInternal(address(this), oldVault, oldShares);
        uint256 oldAssetsAfterRedeem = oldAsset.balanceOf(address(this));

        if (oldAssetsAfterRedeem - oldAssetsBeforeRedeem != oldAssetsToSwap) {
            revert MigrationRedeemFailed();
        }

        oldAsset.approve(address(swapper), oldAssetsToSwap);

        uint256 newAssetsBeforeSwap = newAsset.balanceOf(address(this));
        swapper.swapAssets(swapParams, swapperOtherParams);
        uint256 newAssetsAfterSwap = newAsset.balanceOf(address(this));

        uint256 newAssetsToDeposit = newAssetsAfterSwap - newAssetsBeforeSwap;
        if (newAssetsToDeposit < minNewAssets) {
            revert MigrationSwapFailed();
        }

        depositInternal(msg.sender, address(this), newVault, newAssetsToDeposit, minNewShares);
    }

    /* ========== VIEWS ========== */

    function _self() internal pure returns (VaultSupervisorLib.Storage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }

    function SIGNED_DEPOSIT_TYPEHASH() public pure returns (bytes32) {
        return Constants.SIGNED_DEPOSIT_TYPEHASH;
    }

    function getDeposits(address staker)
        external
        view
        returns (IVault[] memory vaults, IERC20[] memory tokens, uint256[] memory assets, uint256[] memory shares)
    {
        VaultSupervisorLib.Storage storage self = _self();
        uint256 vaultLength = self.stakersVaults[staker].length;
        assets = new uint256[](vaultLength);
        shares = new uint256[](vaultLength);
        tokens = new IERC20[](vaultLength);

        for (uint256 i = 0; i < vaultLength; i++) {
            uint256 _shares = self.stakerShares[staker][self.stakersVaults[staker][i]];
            assets[i] = self.stakersVaults[staker][i].convertToAssets(_shares);
            shares[i] = _shares;
            tokens[i] = IERC20(self.stakersVaults[staker][i].asset());
        }
        return (self.stakersVaults[staker], tokens, assets, shares);
    }

    function implementation() external view override returns (address) {
        return implementation(msg.sender);
    }

    /// @dev Doesn't revert if the vault is not set yet because during `deployVault`
    /// theres a period before we set it to the default flag where the vault
    /// needs an impl to be initialized against
    function implementation(address vault) public view returns (address) {
        VaultSupervisorLib.Storage storage self = _self();
        address vaultImplOverride = self.vaultToImplMap[vault];

        if (vaultImplOverride == Constants.DEFAULT_VAULT_IMPLEMENTATION_FLAG || vaultImplOverride == address(0)) {
            return self.vaultImpl;
        }
        return vaultImplOverride;
    }

    function delegationSupervisor() public view returns (IDelegationSupervisor) {
        VaultSupervisorLib.Storage storage self = _self();
        return self.delegationSupervisor;
    }

    function getUserNonce(address user) external view returns (uint256) {
        VaultSupervisorLib.Storage storage self = _self();
        return self.userNonce[user];
    }

    function getVaults() external view returns (IVault[] memory) {
        VaultSupervisorLib.Storage storage self = _self();
        return self.vaults;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function depositInternal(address staker, address depositor, IVault vault, uint256 amount, uint256 minSharesOut)
        internal
        onlyChildVault(vault)
        whenNotPaused
        returns (uint256 shares)
    {
        VaultSupervisorLib.Storage storage self = _self();
        shares = vault.deposit(amount, depositor);

        if (shares < minSharesOut) revert NotEnoughShares();

        // If the limiter is set, check if the deposit limit is breached
        // allow for it to be set to address(0) in the future to disable the global limit
        if (address(self.limiter) != address(0)) {
            if (self.limiter.isLimitBreached(self.vaults)) revert CrossedDepositLimit();
        }
        // add the returned shares to the staker's existing shares for this Vault
        increaseShares(staker, vault, shares);

        return shares;
    }

    function increaseShares(address staker, IVault vault, uint256 shares) internal {
        // sanity checks on inputs
        if (staker == address(0)) revert ZeroAddress();
        if (shares == 0) revert ZeroShares();

        VaultSupervisorLib.Storage storage self = _self();
        // if they dont have existing shares of this Vault, add it to their strats
        if (self.stakerShares[staker][vault] == 0) {
            if (self.stakersVaults[staker].length >= Constants.MAX_VAULTS_PER_STAKER) revert MaxStakerVault();
            self.stakersVaults[staker].push(vault);
        }

        // add the returned shares to their existing shares for this Vault
        self.stakerShares[staker][vault] += shares;
    }

    /// This function allows `shares` tokens NOT the underlying asset to be withdrawn
    /// for use in other protocols by the holder. You have to return the share tokens back to
    /// this contract to fully withdraw.
    function gimmieShares(IVault vault, uint256 shares) public onlyChildVault(vault) nonReentrant {
        gimmieSharesInternal(vault, shares);
    }

    function gimmieSharesInternal(IVault vault, uint256 shares) internal {
        if (shares == 0) revert ZeroShares();
        IERC20 shareToken = IERC20(vault);

        VaultSupervisorLib.Storage storage self = _self();
        // Verify the user is the owner of these shares
        if (self.stakerShares[msg.sender][vault] < shares) revert NotEnoughShares();

        self.stakerShares[msg.sender][vault] -= shares;

        shareToken.transfer(msg.sender, shares);

        if (self.stakerShares[msg.sender][vault] == 0) {
            removeVaultFromStaker(msg.sender, vault);
        }

        emit GaveShares(msg.sender, address(vault), address(shareToken), shares);
    }

    function returnShares(IVault vault, uint256 shares) external onlyChildVault(vault) nonReentrant {
        increaseShares(msg.sender, vault, shares);

        IERC20 shareToken = IERC20(vault);
        shareToken.transferFrom(msg.sender, address(this), shares);

        emit ReturnedShares(msg.sender, address(vault), address(shareToken), shares);
    }

    function removeVaultFromStaker(address staker, IVault vault) internal {
        VaultSupervisorLib.Storage storage self = _self();
        uint256 vaultsLength = self.stakersVaults[staker].length;
        uint256 i = 0;
        while (i < vaultsLength) {
            if (self.stakersVaults[staker][i] == vault) {
                // Replace this vault with the last vault and then pop the last one off
                // prevents leaving a gap in the array
                self.stakersVaults[staker][i] = self.stakersVaults[staker][vaultsLength - 1];
                break;
            }
            unchecked {
                i++;
            }
        }
        if (i == vaultsLength) revert VaultNotFound();
        self.stakersVaults[staker].pop();
    }

    function cloneVault(bytes memory initData) internal returns (IVault) {
        return IVault(address(new BeaconProxy(address(this), initData)));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function redeemSharesInternal(address redeemTo, IVault vault, uint256 shares) internal {
        vault.redeem(shares, redeemTo, address(this));
    }

    function removeSharesInternal(address staker, IVault vault, uint256 shares) internal {
        if (shares == 0) revert ZeroShares();
        VaultSupervisorLib.Storage storage self = _self();
        uint256 userShares = self.stakerShares[staker][vault];
        if (shares > userShares) revert NotEnoughShares();

        // Already checked above that userShares >= shareAmount
        unchecked {
            userShares = userShares - shares;
        }

        self.stakerShares[staker][vault] = userShares;

        // if user has no more shares, delete
        if (userShares == 0) {
            removeVaultFromStaker(staker, vault);
        }
    }

    /* ========== MODIFIERS ========== */
    modifier onlyChildVault(IVault vault) {
        VaultSupervisorLib.Storage storage self = _self();
        if (self.vaultToImplMap[address(vault)] == address(0)) {
            revert VaultNotAChildVault();
        }
        _;
    }

    modifier onlyDelegationSupervisor() {
        VaultSupervisorLib.Storage storage self = _self();
        if (msg.sender != address(self.delegationSupervisor)) {
            revert NotDelegationSupervisor();
        }
        _;
    }

    /* ========== EVENTS ========== */
    event UpgradedVault(address indexed implementation, address indexed vault);
    event UpgradedAllVaults(address indexed implementation);
}
