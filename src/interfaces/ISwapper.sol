// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ISwapper {
    struct SwapParams {
        IERC20 inputAsset;
        IERC20 outputAsset;
        uint256 inputAmount;
        uint256 minOutputAmount;
    }

    function swapAssets(SwapParams calldata swapParams, bytes calldata domainSpecificParams) external;
    function canSwap(IERC20 input, IERC20 output) external view returns (bool);
}
