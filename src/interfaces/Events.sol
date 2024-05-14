// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

event StartedWithdrawal(
    address indexed vault, address indexed staker, address indexed operator, address withdrawer, uint256 shares
);

event FinishedWithdrawal(
    address indexed vault,
    address indexed staker,
    address indexed operator,
    address withdrawer,
    uint256 shares,
    bytes32 withdrawRoot
);

event NewVault(address indexed vault);
