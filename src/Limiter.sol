// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./interfaces/ILimiter.sol";
import "./interfaces/Errors.sol";
import "./interfaces/IVault.sol";

contract Limiter is ILimiter, Ownable {
    // Denominated in USD with 18 decimals
    uint256 public globalUsdLimit;
    // Since ETH is already 18 decimals a price of 3600 USD per ETH is actually stored as 3600
    uint256 public usdPerEth;

    constructor(uint256 _usdPerEth, uint256 _globalUsdLimit) {
        _initializeOwner(msg.sender);
        usdPerEth = _usdPerEth;
        globalUsdLimit = _globalUsdLimit;
    }

    function isLimitBreached(IVault[] memory vaults) external view returns (bool) {
        uint256 globalDepositsInUsd = computeGlobalDepositsInUsd(vaults);
        return globalDepositsInUsd > globalUsdLimit;
    }

    function remainingGlobalUsdLimit(IVault[] memory vaults) public view returns (uint256) {
        uint256 globalDepositsInUsd = computeGlobalDepositsInUsd(vaults);

        if (globalUsdLimit <= globalDepositsInUsd) return 0;

        return globalUsdLimit - globalDepositsInUsd;
    }

    function computeGlobalDepositsInUsd(IVault[] memory vaults) public view returns (uint256) {
        uint256 globalDepositsInUsd;
        for (uint256 i = 0; i < vaults.length; i++) {
            globalDepositsInUsd += normalizeVaultAssetValue(vaults[i], vaults[i].totalAssets());
        }

        return globalDepositsInUsd;
    }

    function computeUserMaximumDeposit(
        IVault[] memory vaults,
        IVault vaultToDeposit,
        address user,
        uint256 walletBalance
    ) external view returns (uint256) {
        uint256 globalMaxDepositInUsd = remainingGlobalUsdLimit(vaults);
        uint256 vaultMaxDepositInUsd =
            normalizeVaultAssetValue(vaultToDeposit, IERC4626(vaultToDeposit).maxDeposit(user));
        uint256 userMaxDepositInUsd = normalizeVaultAssetValue(vaultToDeposit, walletBalance);

        uint256 minimumMaxDepositInUsd;
        // This block computes MIN( userMaxDepositInUsd, vaultMaxDepositInUsd, globalMaxDepositInUsd )
        minimumMaxDepositInUsd = globalMaxDepositInUsd;
        if (vaultMaxDepositInUsd < minimumMaxDepositInUsd) {
            minimumMaxDepositInUsd = vaultMaxDepositInUsd;
        }
        if (userMaxDepositInUsd < minimumMaxDepositInUsd) {
            minimumMaxDepositInUsd = userMaxDepositInUsd;
        }

        return denormalizeVaultAssetValue(vaultToDeposit, minimumMaxDepositInUsd);
    }

    function setGlobalUsdLimit(uint256 _limit) external onlyOwner {
        globalUsdLimit = _limit;
    }

    function setUsdPerEth(uint256 _usdPerEth) external onlyOwner {
        usdPerEth = _usdPerEth;
    }

    function normalizeVaultAssetValue(IVault vault, uint256 value) public view returns (uint256) {
        if (vault.assetType() == IVault.AssetType.STABLE) {
            return value * (10 ** uint256(18 - vault.decimals()));
        } else if (vault.assetType() == IVault.AssetType.ETH) {
            return value * usdPerEth;
        } else {
            revert UnsupportedAsset();
        }
    }

    function denormalizeVaultAssetValue(IVault vault, uint256 value) public view returns (uint256) {
        if (vault.assetType() == IVault.AssetType.STABLE) {
            return value / (10 ** uint256(18 - vault.decimals()));
        } else if (vault.assetType() == IVault.AssetType.ETH) {
            return value / usdPerEth;
        } else {
            revert UnsupportedAsset();
        }
    }
}
