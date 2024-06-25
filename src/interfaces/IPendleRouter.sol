// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

interface IPendleRouter {
    /// @dev Source: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/router/swap-aggregator/IPSwapAggregator.sol#L11-L17
    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        // ETH_WETH not used in Aggregator
        ETH_WETH
    }

    /// @dev Source: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/router/swap-aggregator/IPSwapAggregator.sol#L4-L9
    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    /// @dev Source: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/interfaces/IPAllActionTypeV3.sol#L19-L27
    struct TokenInput {
        // TOKEN DATA
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    /// @dev Source: https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/interfaces/IPAllActionTypeV3.sol#L29-L37
    struct TokenOutput {
        // TOKEN DATA
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        // AGGREGATOR DATA
        address pendleSwap;
        SwapData swapData;
    }

    /// @dev Source: https://github.com/pendle-finance/pendle-core-v2-public/blob/97b1b9708478b389f9540d71816c7894aab6bb77/contracts/interfaces/IPActionMiscV3.sol#L153-L158
    function mintPyFromToken(address receiver, address YT, uint256 minPyOut, TokenInput calldata input)
        external
        payable
        returns (uint256 netPyOut, uint256 netSyInterm);

    /// @dev Source: https://github.com/pendle-finance/pendle-core-v2-public/blob/97b1b9708478b389f9540d71816c7894aab6bb77/contracts/interfaces/IPActionMiscV3.sol#L160-L165
    function redeemPyToToken(address receiver, address YT, uint256 netPyIn, TokenOutput calldata output)
        external
        returns (uint256 netTokenOut, uint256 netSyInterm);
}
