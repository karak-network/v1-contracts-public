// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IVault.sol";
import "./ILimiter.sol";
import {ISwapper} from "./ISwapper.sol";

interface IVaultSupervisor {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function getDeposits(address staker)
        external
        view
        returns (IVault[] memory vaults, IERC20[] memory tokens, uint256[] memory assets, uint256[] memory shares);
    function initialize(address _delegationSupervisor, address _vaultImpl, ILimiter _limiter, address _manager)
        external;
    function redeemShares(address staker, IVault vault, uint256 shares) external;
    function removeShares(address staker, IVault vault, uint256 shares) external;
    function deposit(IVault vault, uint256 amount, uint256 minSharesOut) external returns (uint256);
    function deployVault(IERC20 depositToken, string memory name, string memory symbol, IVault.AssetType assetType)
        external
        returns (IVault);
    function runAdminOperation(IVault vault, bytes calldata fn) external returns (bytes memory);
    function depositWithSignature(
        IVault vault,
        address user,
        uint256 value,
        uint256 minSharesOut,
        uint256 deadline,
        Signature calldata permit,
        Signature calldata vaultAllowance
    ) external returns (uint256);
    function SIGNED_DEPOSIT_TYPEHASH() external returns (bytes32);
    function getUserNonce(address user) external returns (uint256);
    function registerSwapperForRoutes(IERC20[] calldata inputAssets, IERC20[] calldata outputAssets, ISwapper swapper)
        external;
    function vaultSwap(
        IVault vault,
        IVault.SwapAssetParams calldata params,
        uint256 minNewAssetAmount,
        bytes calldata swapperParams
    ) external;
    function migrate(
        IVault oldVault,
        IVault newVault,
        uint256 oldShares,
        uint256 minNewShares,
        bytes calldata swapperParams
    ) external;
}
