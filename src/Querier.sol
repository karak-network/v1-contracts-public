// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "solady/src/auth/Ownable.sol";

import "./interfaces/IVaultSupervisor.sol";
import "./interfaces/IDelegationSupervisor.sol";
import "./interfaces/IQuerier.sol";

contract Querier is IQuerier, Ownable {
    IVaultSupervisor public vaultSupervisor;
    IDelegationSupervisor public delegationSupervisor;

    /* ========== MUTATIVE FUNCTIONS ========== */

    constructor(address _vaultSupervisor, address _delegationSupervisor) {
        _initializeOwner(msg.sender);
        vaultSupervisor = IVaultSupervisor(_vaultSupervisor);
        delegationSupervisor = IDelegationSupervisor(_delegationSupervisor);
    }

    function setVaultSupervisor(IVaultSupervisor _vaultSupervisor) external onlyOwner {
        vaultSupervisor = _vaultSupervisor;
    }

    function setDelegationSupervisor(IDelegationSupervisor _delegationSupervisor) external onlyOwner {
        delegationSupervisor = _delegationSupervisor;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getDeposits(address[] memory stakers) external view returns (DepositResult[] memory) {
        DepositResult[] memory results = new DepositResult[](stakers.length);
        for (uint256 i = 0; i < stakers.length; i++) {
            IVault[] memory vaults;
            IERC20[] memory tokens;
            uint256[] memory assets;
            uint256[] memory shares;
            (vaults, tokens, assets, shares) = vaultSupervisor.getDeposits(stakers[i]);
            results[i] = (DepositResult(stakers[i], vaults, tokens, assets, shares));
        }
        return results;
    }

    function getWithdraws(address staker)
        external
        view
        returns (Withdraw.QueuedWithdrawal[] memory allWithdrawals, bool[] memory isWithdrawPending)
    {
        allWithdrawals = delegationSupervisor.fetchQueuedWithdrawals(staker);
        isWithdrawPending = new bool[](allWithdrawals.length);

        for (uint256 i = 0; i < allWithdrawals.length; i++) {
            Withdraw.QueuedWithdrawal memory withdrawal = allWithdrawals[i];
            if (delegationSupervisor.isWithdrawPending(withdrawal)) {
                isWithdrawPending[i] = true;
            } else {
                isWithdrawPending[i] = false;
            }
        }
    }
}
