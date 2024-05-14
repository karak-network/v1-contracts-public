// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "./IVault.sol";

interface ILimiter {
    function globalUsdLimit() external view returns (uint256);
    function usdPerEth() external view returns (uint256);
    function isLimitBreached(IVault[] calldata vaults) external view returns (bool);
    function remainingGlobalUsdLimit(IVault[] memory vaults) external view returns (uint256);
    function computeGlobalDepositsInUsd(IVault[] memory vaults) external view returns (uint256);
    function computeUserMaximumDeposit(
        IVault[] memory vaults,
        IVault vaultToDeposit,
        address user,
        uint256 walletBalance
    ) external view returns (uint256);
    function setGlobalUsdLimit(uint256 _limit) external;
    function setUsdPerEth(uint256 _usdPerEth) external;
}
