// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "./IVault.sol";
import "../entities/Withdraw.sol";

interface IDelegationSupervisor {
    function withdrawalDelay() external view returns (uint256);

    function initialize(address vaultSupervisor, uint256 minWithdrawDelay, address manager) external;

    function startWithdraw(Withdraw.WithdrawRequest[] calldata withdrawRequest)
        external
        returns (bytes32[] memory withdrawalRoots, Withdraw.QueuedWithdrawal[] memory);

    function finishWithdraw(Withdraw.QueuedWithdrawal[] calldata withdrawals) external;

    function pause(bool toPause) external;

    function fetchQueuedWithdrawals(address staker)
        external
        view
        returns (Withdraw.QueuedWithdrawal[] memory queuedWithdrawals);

    function isWithdrawPending(Withdraw.QueuedWithdrawal calldata withdrawal) external view returns (bool);
}
