// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "./DelegationSupervisorLib.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IVaultSupervisor.sol";
import "../interfaces/Errors.sol";
import "../interfaces/Events.sol";

library Withdraw {
    struct QueuedWithdrawal {
        address staker;
        address delegatedTo;
        uint256 nonce;
        uint256 start;
        WithdrawRequest request;
    }

    struct WithdrawRequest {
        IVault[] vaults;
        uint256[] shares;
        address withdrawer;
    }

    function finishStartedWithdrawal(
        QueuedWithdrawal calldata withdrawal,
        DelegationSupervisorLib.Storage storage delegationSupervisor
    ) internal {
        bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);
        if (withdrawal.request.withdrawer != msg.sender) revert WithdrawerNotCaller();
        if (withdrawal.start + delegationSupervisor.withdrawalDelay > block.timestamp) {
            revert MinWithdrawDelayNotPassed();
        }
        if (!delegationSupervisor.pendingWithdrawals[withdrawalRoot]) revert WithdrawAlreadyCompleted();
        delete delegationSupervisor.pendingWithdrawals[withdrawalRoot];

        for (uint256 i = 0; i < withdrawal.request.vaults.length; i++) {
            delegationSupervisor.vaultSupervisor.redeemShares(
                msg.sender, withdrawal.request.vaults[i], withdrawal.request.shares[i]
            );
            emit FinishedWithdrawal(
                address(withdrawal.request.vaults[i]),
                withdrawal.staker,
                withdrawal.delegatedTo,
                withdrawal.request.withdrawer,
                withdrawal.request.shares[i],
                withdrawalRoot
            );
        }
    }

    function calculateWithdrawalRoot(QueuedWithdrawal memory withdrawal) internal pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    function validate(Withdraw.WithdrawRequest calldata withdrawalRequest) internal view {
        // Length Checks
        if (withdrawalRequest.shares.length == 0 || withdrawalRequest.vaults.length == 0) revert NoElementsInArray();
        if (withdrawalRequest.shares.length != withdrawalRequest.vaults.length) revert ArrayLengthsNotEqual();

        // ACL checks
        if (withdrawalRequest.withdrawer != msg.sender) revert NotStaker();
    }
}
