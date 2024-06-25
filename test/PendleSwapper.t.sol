// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {PendleSwapper} from "../src/PendleSwapper.sol";
import {IPendleRouter} from "../src/interfaces/IPendleRouter.sol";
import {IVaultSupervisor} from "../src/interfaces/IVaultSupervisor.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console2.sol";

contract PendleSwapperTest is Test, Script {
    uint256 mainnetFork;

    PendleSwapper pendleSwapper;
    IVault vault;
    IERC20 oldPTToken;
    IERC20 oldYTToken;
    IERC20 underlyingToken;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        oldPTToken = IERC20(0x5cb12D56F5346a016DBBA8CA90635d82e6D1bcEa); // PT rswETH 27JUN2024
        oldYTToken = IERC20(0x4AfdB1B0f9A56922e398D29239453e6A06148eD0); // YT rswETH 27JUN2024
        underlyingToken = IERC20(0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0); // rswETH
        vault = IVault(0xcf1110BCA74890eAE1aad534eC3A03f16956ebEb); // Karak rswETH Vault
        pendleSwapper = new PendleSwapper(address(this), IPendleRouter(0x888888888889758F76e7103c6CbF23ABbF58F946));
    }

    function test_can_swap() public {
        vm.assertFalse(pendleSwapper.canSwap(oldPTToken, underlyingToken));
        setupRedeemRoute();
        vm.assertTrue(pendleSwapper.canSwap(oldPTToken, underlyingToken));
    }

    function test_swap_fail() public {
        setupRedeemRoute();
        vm.warp(1719375040); // Wed Jun 26 2024 04:10:40 GMT+0000
        vm.startPrank(address(vault));

        uint256 oldPTTokenBalance = oldPTToken.balanceOf(address(vault));
        oldPTToken.approve(address(pendleSwapper), oldPTTokenBalance);

        ISwapper.SwapParams memory swapParams = ISwapper.SwapParams({
            inputAsset: oldPTToken,
            outputAsset: underlyingToken,
            inputAmount: oldPTTokenBalance,
            minOutputAmount: 1
        });

        bytes memory swapperOtherParams = abi.encode(0);

        vm.expectRevert(); // TODO: Expect the actual error if possible
        pendleSwapper.swapAssets(swapParams, swapperOtherParams);

        vm.stopPrank();
    }

    function test_swap_successful() public {
        setupRedeemRoute();
        vm.warp(1719547840); // Fri Jun 28 2024 04:10:40 GMT+0000
        vm.startPrank(address(vault));

        uint256 oldPTTokenBalance = oldPTToken.balanceOf(address(vault));
        oldPTToken.approve(address(pendleSwapper), oldPTTokenBalance);

        uint256 oldPTTokenBalanceBefore = oldPTToken.balanceOf(address(vault));
        uint256 underlyingBalanceBefore = underlyingToken.balanceOf(address(vault));

        ISwapper.SwapParams memory swapParams = ISwapper.SwapParams({
            inputAsset: oldPTToken,
            outputAsset: underlyingToken,
            inputAmount: oldPTTokenBalance,
            // NOTE: derived from running the script and comparing the logs below
            minOutputAmount: (oldPTTokenBalance * 9892) / 10000
        });

        bytes memory swapperOtherParams = abi.encode(0);

        pendleSwapper.swapAssets(swapParams, swapperOtherParams);

        uint256 oldPTTokenBalanceAfter = oldPTToken.balanceOf(address(vault));
        uint256 underlyingBalanceAfter = underlyingToken.balanceOf(address(vault));

        console2.log("oldPTTokenBalanceBefore", oldPTTokenBalanceBefore);
        console2.log("oldPTTokenBalanceAfter", oldPTTokenBalanceAfter);

        console2.log("underlyingBalanceBefore", underlyingBalanceBefore);
        console2.log("underlyingBalanceAfter", underlyingBalanceAfter);

        vm.stopPrank();
    }

    function run() public {
        test_swap_successful();
    }

    function setupRedeemRoute() internal {
        IERC20[] memory inputAssets = new IERC20[](1);
        inputAssets[0] = oldPTToken;

        IERC20[] memory outputAssets = new IERC20[](1);
        outputAssets[0] = underlyingToken;

        PendleSwapper.RouteConfig[] memory routes = new PendleSwapper.RouteConfig[](1);
        routes[0] = PendleSwapper.RouteConfig({
            routeType: PendleSwapper.RouteType.REDEEM,
            config: abi.encode(
                PendleSwapper.RedeemSwapParams({
                    YT: address(oldYTToken),
                    tokenOut: address(underlyingToken),
                    tokenRedeemSy: address(underlyingToken),
                    pendleSwap: address(0),
                    swapData: IPendleRouter.SwapData({
                        swapType: IPendleRouter.SwapType.NONE,
                        extRouter: address(0),
                        needScale: false,
                        extCalldata: ""
                    })
                })
            )
        });

        pendleSwapper.updateRoutes(inputAssets, outputAssets, routes);
    }
}
