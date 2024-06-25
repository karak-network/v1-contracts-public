// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISwapper} from "./interfaces/ISwapper.sol";
import {IPendleRouter} from "./interfaces/IPendleRouter.sol";
import "./interfaces/Errors.sol";

contract PendleSwapper is ISwapper, Ownable, Pausable, ReentrancyGuard {
    enum RouteType {
        NONE,
        MINT,
        REDEEM
    }

    struct RouteConfig {
        RouteType routeType;
        bytes config;
    }

    /// @dev Based on IPendleRouter.mintPyFromToken(receiver, YT, minPyOut, input);
    struct MintSwapParams {
        address YT; // new YT token
        // TOKEN DATA
        address tokenIn;
        address tokenMintSy;
        // AGGREGATOR DATA
        address pendleSwap;
        IPendleRouter.SwapData swapData;
    }

    /// @dev Based on IPendleRouter.redeemPyToToken(receiver, YT, netPyIn, output);
    struct RedeemSwapParams {
        address YT;
        // TOKEN DATA
        address tokenOut;
        address tokenRedeemSy;
        // AGGREGATOR DATA
        address pendleSwap;
        IPendleRouter.SwapData swapData;
    }

    IPendleRouter public pendleRouter;
    mapping(IERC20 inputAsset => mapping(IERC20 outputAsset => RouteConfig config)) public inputToOutputToRoute;

    constructor(address _owner, IPendleRouter _pendleRouter) {
        _initializeOwner(_owner);
        pendleRouter = _pendleRouter;
    }

    function updatePendleRouter(IPendleRouter newPendleRouter) external onlyOwner {
        pendleRouter = newPendleRouter;
    }

    function updateRoutes(IERC20[] calldata inputAssets, IERC20[] calldata outputAssets, RouteConfig[] calldata routes)
        external
        onlyOwner
    {
        updateRoutesInternal(inputAssets, outputAssets, routes);
    }

    function canSwap(IERC20 input, IERC20 output) external view returns (bool) {
        if (paused()) return false;

        return inputToOutputToRoute[input][output].routeType != RouteType.NONE;
    }

    function swapAssets(SwapParams calldata swapParams, bytes calldata domainSpecificParams)
        external
        whenNotPaused
        nonReentrant
    {
        RouteConfig memory route = inputToOutputToRoute[swapParams.inputAsset][swapParams.outputAsset];
        if (route.routeType == RouteType.NONE) {
            revert CannotSwap();
        }

        IERC20(swapParams.inputAsset).transferFrom(msg.sender, address(this), swapParams.inputAmount);

        if (route.routeType == RouteType.MINT) {
            handleMintSwap(swapParams, route.config, domainSpecificParams);
        } else if (route.routeType == RouteType.REDEEM) {
            handleRedeemSwap(swapParams, route.config, domainSpecificParams);
        }
    }

    function updateRoutesInternal(
        IERC20[] calldata inputAssets,
        IERC20[] calldata outputAssets,
        RouteConfig[] calldata routes
    ) internal {
        uint256 expectedLength = inputAssets.length;
        if (outputAssets.length != expectedLength || routes.length != expectedLength) {
            revert LengthDoesNotMatch();
        }

        for (uint256 i = 0; i < expectedLength; i++) {
            inputToOutputToRoute[inputAssets[i]][outputAssets[i]] = routes[i];
        }
    }

    function handleMintSwap(SwapParams calldata dynamicParams, bytes memory domainConfig, bytes calldata domainParams)
        internal
    {
        MintSwapParams memory staticParams = abi.decode(domainConfig, (MintSwapParams));
        if (
            staticParams.tokenIn != staticParams.tokenMintSy
                || address(dynamicParams.inputAsset) != staticParams.tokenMintSy
        ) {
            revert InvalidSwapParams();
        }

        (address ytReceiver, uint256 minYt) = abi.decode(domainParams, (address, uint256));

        dynamicParams.inputAsset.approve(address(pendleRouter), dynamicParams.inputAmount);
        uint256 ptBefore = dynamicParams.outputAsset.balanceOf(address(this));
        uint256 ytBefore = IERC20(staticParams.YT).balanceOf(address(this));

        IPendleRouter(pendleRouter).mintPyFromToken(
            address(this),
            staticParams.YT, // YT address
            dynamicParams.minOutputAmount + minYt, // dynamic - PY = PT + YT - TODO: Double check this
            IPendleRouter.TokenInput({
                tokenIn: staticParams.tokenIn, // underlying
                netTokenIn: dynamicParams.inputAmount, // dynamic
                tokenMintSy: staticParams.tokenMintSy, // underlying
                pendleSwap: staticParams.pendleSwap, // 0x0
                swapData: staticParams.swapData // empty
            })
        );

        uint256 ptReceived = dynamicParams.outputAsset.balanceOf(address(this)) - ptBefore;
        uint256 ytReceived = IERC20(staticParams.YT).balanceOf(address(this)) - ytBefore;

        if (ptReceived < dynamicParams.minOutputAmount || ytReceived < minYt) {
            revert PendleSwapFailed();
        }

        dynamicParams.outputAsset.transfer(msg.sender, ptReceived);
        IERC20(staticParams.YT).transfer(ytReceiver, ytReceived);
    }

    function handleRedeemSwap(SwapParams calldata dynamicParams, bytes memory domainConfig, bytes calldata domainParams)
        internal
    {
        RedeemSwapParams memory staticParams = abi.decode(domainConfig, (RedeemSwapParams));
        // domainParams is NOT used here (i.e. it can be empty/arbitrary)

        if (
            staticParams.tokenOut != staticParams.tokenRedeemSy
                || address(dynamicParams.outputAsset) != staticParams.tokenRedeemSy
        ) {
            revert InvalidSwapParams();
        }

        dynamicParams.inputAsset.approve(address(pendleRouter), dynamicParams.inputAmount);
        uint256 underlyingBefore = dynamicParams.outputAsset.balanceOf(address(this));

        IPendleRouter(pendleRouter).redeemPyToToken(
            address(this),
            staticParams.YT, // YT address
            dynamicParams.inputAmount, // dynamic
            IPendleRouter.TokenOutput({
                tokenOut: staticParams.tokenOut, // underlying
                minTokenOut: dynamicParams.minOutputAmount, // dynamic
                tokenRedeemSy: staticParams.tokenRedeemSy, // underlying
                pendleSwap: staticParams.pendleSwap, // 0x0
                swapData: staticParams.swapData // empty
            })
        );

        uint256 underlyingReceived = dynamicParams.outputAsset.balanceOf(address(this)) - underlyingBefore;

        if (underlyingReceived < dynamicParams.minOutputAmount) {
            revert PendleSwapFailed();
        }

        dynamicParams.outputAsset.transfer(msg.sender, underlyingReceived);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transfer(owner(), tokenAmount);
    }

    function recoverETH(uint256 ethAmount) external onlyOwner {
        payable(owner()).transfer(ethAmount);
    }
}
