// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Staker} from "./Staker.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IVaultSupervisor} from "../interfaces/IVaultSupervisor.sol";
import "../interfaces/Errors.sol";
import "../interfaces/Constants.sol";

library DelegationSupervisorLib {
    /// @custom:storage-location erc7201:delegationsupervisor.storage
    struct Storage {
        mapping(bytes32 => bool) pendingWithdrawals;
        mapping(address => mapping(bytes32 => bool)) delegationApproverSaltIsSpent;
        mapping(address staker => Staker.StakerState state) stakers;
        uint256 withdrawalDelay;
        IVaultSupervisor vaultSupervisor;
    }

    function initOrUpdate(Storage storage self, address vaultSupervisor, uint256 withdrawDelay) internal {
        if (withdrawDelay > Constants.MAX_WITHDRAWAL_DELAY) revert InvalidWithdrawalDelay();
        self.withdrawalDelay = withdrawDelay;
        self.vaultSupervisor = IVaultSupervisor(vaultSupervisor);
    }

    function updateMinWithdrawDelay(Storage storage self, uint256 withdrawDelay) internal {
        if (withdrawDelay > Constants.MAX_WITHDRAWAL_DELAY) revert InvalidWithdrawalDelay();
        self.withdrawalDelay = withdrawDelay;
    }
}
