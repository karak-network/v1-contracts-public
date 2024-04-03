// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Withdraw} from "../entities/Withdraw.sol";

import "./IVault.sol";
import "./IDelegationSupervisor.sol";

interface IQuerier {
    struct DepositResult {
        address user;
        IVault[] vaults;
        IERC20[] tokens;
        uint256[] assets;
        uint256[] shares;
    }

    function setVaultSupervisor(IVaultSupervisor _vaultSupervisor) external;
    function setDelegationSupervisor(IDelegationSupervisor _delegationSupervisor) external;
    function getDeposits(address[] memory stakers) external view returns (DepositResult[] memory);
    function getWithdraws(address staker)
        external
        view
        returns (Withdraw.QueuedWithdrawal[] memory allWithdrawals, bool[] memory isWithdrawPending);
}
