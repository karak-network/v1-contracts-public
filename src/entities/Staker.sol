// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "./Withdraw.sol";

library Staker {
    struct StakerState {
        address delegatee; // staker this staker is delegating to
        uint256 nonce;
        uint256 totalWithdrawsQueued;
        Withdraw.QueuedWithdrawal[] queuedWithdrawals;
    }
}
