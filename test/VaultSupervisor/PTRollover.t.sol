// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Vault} from "../../src/Vault.sol";
import {ERC1967Factory} from "solady/src/utils/ERC1967Factory.sol";
import {VaultSupervisor} from "../../src/VaultSupervisor.sol";
import {PendleSwapper} from "../../src/PendleSwapper.sol";
import {IPendleRouter} from "../../src/interfaces/IPendleRouter.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";

import "../../script/config/PTRolloverConfig.sol";

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console2.sol";

struct PTRolloverConfig {
    bool initialized;
    IERC20 underlying;
    IERC20 oldPT;
    IERC20 oldYT;
    IVault oldKarakPTVault;
    IERC20 newPT;
    IERC20 newYT;
    IVault newKarakPTVault;
    string underlyingName;
    string underlyingSymbol;
    uint256 minUnderlyingAmount;
}

address constant ERC1967_FACTORY_ADDRESS = 0x947804256C9c46967cC55bBBBF6C0E93923AFf2C;
address constant VAULT_SUPERVISOR_ADDRESS = 0x54e44DbB92dBA848ACe27F44c0CB4268981eF1CC;
address constant PENDLE_ROUTER_V4 = 0x888888888889758F76e7103c6CbF23ABbF58F946;

contract PTRolloverTest is Test, Script {
    bool isScript = false;
    uint256 mainnetFork;
    PTRolloverConfig[] rolloverConfigs;

    VaultSupervisor vaultSupervisor = VaultSupervisor(VAULT_SUPERVISOR_ADDRESS);
    PendleSwapper pendleSwapper;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        // TODO(Drew): Maybe we should also pin this to a block?
        //             Actually can leave as is for now and can do that closer to expiry to have more accurate state
        //             Main implication is that the min amounts will change
        vm.warp(1719547840); // Fri Jun 28 2024 04:10:40 GMT+0000

        // Upgrade the VaultSupervisor to enable new swap and migrate functionality
        upgradeVaultSupervisor(ERC1967Factory(ERC1967_FACTORY_ADDRESS), address(vaultSupervisor));

        PTRolloverConfig[] memory _configs = setupRolloverConfigs();
        for (uint256 i = 0; i < _configs.length; i++) {
            if (_configs[i].initialized) {
                rolloverConfigs.push(_configs[i]);
            }
        }

        // Upgrade the old Karak PT vaults to enable new swap and migrate functionality
        startTx(vaultSupervisor.owner());
        address newVaultImpl = address(new Vault());
        stopTx();

        for (uint256 i = 0; i < rolloverConfigs.length; i++) {
            upgradeVault(vaultSupervisor, address(rolloverConfigs[i].oldKarakPTVault), newVaultImpl);
        }

        pendleSwapper = setupPendleSwapper(rolloverConfigs);
    }

    function run() public {
        isScript = true;
    }

    function test_admin_vault_swap() public {
        for (uint256 i = 0; i < rolloverConfigs.length; i++) {
            PTRolloverConfig memory config = rolloverConfigs[i];

            console2.log("Testing admin vault swap for vault", config.oldKarakPTVault.name());

            uint256 ptBalanceBefore = config.oldPT.balanceOf(address(config.oldKarakPTVault));
            uint256 underlyingBalanceBefore = config.underlying.balanceOf(address(config.oldKarakPTVault));
            console2.log("PT Balance Before", ptBalanceBefore);
            console2.log("Underlying Balance Before", underlyingBalanceBefore);

            assertGt(ptBalanceBefore, 0);
            assertEq(underlyingBalanceBefore, 0);

            startTx(vaultSupervisor.owner());
            vaultSupervisor.vaultSwap(
                config.oldKarakPTVault,
                IVault.SwapAssetParams({
                    newDepositToken: config.underlying,
                    name: config.underlyingName,
                    symbol: config.underlyingSymbol,
                    assetType: IVault.AssetType.ETH,
                    assetLimit: config.oldKarakPTVault.assetLimit() // TODO(Drew): Update this if you want
                }),
                config.minUnderlyingAmount,
                bytes("")
            );
            stopTx();

            uint256 ptBalanceAfter = config.oldPT.balanceOf(address(config.oldKarakPTVault));
            uint256 underlyingBalanceAfter = config.underlying.balanceOf(address(config.oldKarakPTVault));
            console2.log("PT Balance After", ptBalanceAfter);
            console2.log("Underlying Balance After", underlyingBalanceAfter);

            assertEq(ptBalanceAfter, 0);
            assertGt(underlyingBalanceAfter, 0);

            console2.log();
        }
    }

    function test_user_vault_migrate() public {}

    function setupRolloverConfigs() internal returns (PTRolloverConfig[] memory configs) {
        configs = new PTRolloverConfig[](3);

        PTRolloverConfig memory rswETHConfig = createRolloverConfig(
            rswETH,
            PT_rswETH_27JUN2024,
            YT_rswETH_27JUN2024,
            PT_rswETH_NEXT,
            YT_rswETH_NEXT,
            Karak_PT_rswETH_27JUN2024,
            Karak_PT_rswETH_NEXT,
            "Karak PT rswETH NEXT",
            "K-PT-rswETH-NEXT",
            IVault.AssetType.ETH,
            "Karak Swell rswETH",
            "K-rswETH",
            1 // TODO(Drew): Check logs after updating config and update this
        );

        if (rswETHConfig.initialized) {
            configs[0] = rswETHConfig;
        }

        PTRolloverConfig memory weETHConfig = createRolloverConfig(
            weETH,
            PT_weETH_27JUN2024,
            YT_weETH_27JUN2024,
            PT_weETH_NEXT,
            YT_weETH_NEXT,
            Karak_PT_weETH_27JUN2024,
            Karak_PT_weETH_NEXT,
            "Karak PT weETH NEXT",
            "K-PT-weETH-NEXT",
            IVault.AssetType.ETH,
            "Karak EtherFi weETH",
            "K-weETH",
            23553665383987689774057 // TODO(Drew): Check logs after updating config and update this
        );

        if (weETHConfig.initialized) {
            configs[1] = weETHConfig;
        }

        PTRolloverConfig memory rsETHConfig = createRolloverConfig(
            rsETH,
            PT_rsETH_27JUN2024,
            YT_rsETH_27JUN2024,
            PT_rsETH_NEXT,
            YT_rsETH_NEXT,
            Karak_PT_rsETH_27JUN2024,
            Karak_PT_rsETH_NEXT,
            "Karak PT rsETH NEXT",
            "K-PT-rsETH-NEXT",
            IVault.AssetType.ETH,
            "Karak Kelp rsETH",
            "K-rsETH",
            14587598354127035768226 // TODO(Drew): Check logs after updating config and update this
        );

        if (rsETHConfig.initialized) {
            configs[2] = rsETHConfig;
        }
    }

    function createRolloverConfig(
        address underlying,
        address oldPT,
        address oldYT,
        address newPT,
        address newYT,
        address oldKarakPTVault,
        address newKarakPTVault,
        string memory name,
        string memory symbol,
        IVault.AssetType assetType,
        string memory underlyingName,
        string memory underlyingSymbol,
        uint256 minUnderlyingAmount
    ) internal returns (PTRolloverConfig memory config) {
        if (newPT != address(0) && newYT != address(0)) {
            IVault newVault;
            if (newKarakPTVault != address(0)) {
                newVault = IVault(newKarakPTVault);
            } else {
                newVault = deployNewVault(IVault(oldKarakPTVault), IERC20(newPT), name, symbol, assetType);
            }

            config = PTRolloverConfig({
                initialized: true,
                underlying: IERC20(underlying),
                oldPT: IERC20(oldPT),
                oldYT: IERC20(oldYT),
                oldKarakPTVault: IVault(oldKarakPTVault),
                newPT: IERC20(newPT),
                newYT: IERC20(newYT),
                newKarakPTVault: newVault,
                underlyingName: underlyingName,
                underlyingSymbol: underlyingSymbol,
                minUnderlyingAmount: minUnderlyingAmount
            });
        }
    }

    function deployNewVault(
        IVault oldVault,
        IERC20 depositToken,
        string memory name,
        string memory symbol,
        IVault.AssetType assetType
    ) internal returns (IVault newVault) {
        VaultSupervisor vaultSupervisor = VaultSupervisor(oldVault.owner());
        address admin = vaultSupervisor.owner();

        startTx(admin);
        newVault = vaultSupervisor.deployVault(depositToken, name, symbol, assetType);
        stopTx();
    }

    function upgradeVaultSupervisor(ERC1967Factory factory, address proxy) internal {
        address proxyAdmin = factory.adminOf(proxy);

        startTx(proxyAdmin);
        address newVaultSupervisorImpl = address(new VaultSupervisor());
        factory.upgrade(proxy, newVaultSupervisorImpl);
        stopTx();
    }

    function upgradeVault(VaultSupervisor vaultSupervisor, address vault, address newVaultImpl) internal {
        address owner = vaultSupervisor.owner();

        startTx(owner);
        vaultSupervisor.changeImplementationForVault(vault, newVaultImpl);
        stopTx();
    }

    function setupPendleSwapper(PTRolloverConfig[] storage configs) internal returns (PendleSwapper pendleSwapper) {
        uint256 totalRoutes = configs.length * 2;

        IERC20[] memory inputAssets = new IERC20[](totalRoutes);
        IERC20[] memory outputAssets = new IERC20[](totalRoutes);
        PendleSwapper.RouteConfig[] memory routes = new PendleSwapper.RouteConfig[](totalRoutes);

        uint256 j = 0;
        for (uint256 i = 0; i < configs.length; i++) {
            if (!configs[i].initialized) revert("Uninitialized config found");

            inputAssets[j] = configs[i].oldPT;
            outputAssets[j] = configs[i].underlying;
            routes[j] = PendleSwapper.RouteConfig({
                routeType: PendleSwapper.RouteType.REDEEM,
                config: abi.encode(
                    PendleSwapper.RedeemSwapParams({
                        YT: address(configs[i].oldYT),
                        tokenOut: address(configs[i].underlying),
                        tokenRedeemSy: address(configs[i].underlying),
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

            j++;

            inputAssets[j] = configs[i].underlying;
            outputAssets[j] = configs[i].newPT;
            routes[j] = PendleSwapper.RouteConfig({
                routeType: PendleSwapper.RouteType.MINT,
                config: abi.encode(
                    PendleSwapper.MintSwapParams({
                        YT: address(configs[i].newYT),
                        tokenIn: address(configs[i].underlying),
                        tokenMintSy: address(configs[i].underlying),
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

            j++;
        }

        // TODO(Drew): If you want the owner of the PendleSwapper to be different, update this line
        address owner = vaultSupervisor.owner();
        startTx(owner);
        pendleSwapper = new PendleSwapper(owner, IPendleRouter(PENDLE_ROUTER_V4));
        pendleSwapper.updateRoutes(inputAssets, outputAssets, routes);
        vaultSupervisor.registerSwapperForRoutes(inputAssets, outputAssets, ISwapper(pendleSwapper));
        stopTx();
    }

    function startTx(address msgSender) internal {
        if (isScript) {
            vm.startBroadcast(msgSender);
        } else {
            vm.startPrank(msgSender);
        }
    }

    function stopTx() internal {
        if (isScript) {
            vm.stopBroadcast();
        } else {
            vm.stopPrank();
        }
    }
}
