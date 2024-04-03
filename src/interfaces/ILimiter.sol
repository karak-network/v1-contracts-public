// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "./IVault.sol";

interface ILimiter {
    function isLimitBreached(IVault[] calldata vaults) external returns (bool);
    function setGlobalUsdLimit(uint256 _limit) external;
    function setUsdPerEth(uint256 _usdPerEth) external;
}
