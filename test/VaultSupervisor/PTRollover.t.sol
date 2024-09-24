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
import {PTRolloverChainConfig} from "../../script/config/PTRolloverChainConfig.sol";

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
    string karakVaultSwapName;
    string karakVaultSwapSymbol;
    uint256 minUnderlyingAmount;
    address testUser;
}

contract PTRolloverTest is Test, Script {
    PTRolloverChainConfig.Chain[] runForChains;
    PTRolloverChainConfig.Chain currentChain;

    bool isScript = false;
    string chainName;
    string currentForkUrl;
    uint256 currentFork;
    uint256 pinToBlock = 0;
    uint256 warpToTimestamp = 0;
    PTRolloverConfig[] rolloverConfigs;

    VaultSupervisor vaultSupervisor;
    PendleSwapper pendleSwapper;

    function setUp() public {
        runForChains = [PTRolloverChainConfig.Chain.Mainnet, PTRolloverChainConfig.Chain.Arbitrum];
    }

    function run() public {
        isScript = true;
    }

    // function test_admin_vault_swap() public {
    //     for (uint256 i = 0; i < runForChains.length; i++) {
    //         setUpForChain(runForChains[i]);
    //         for (uint256 i = 0; i < rolloverConfigs.length; i++) {
    //             PTRolloverConfig memory config = rolloverConfigs[i];

    //             console2.log("Testing admin vault swap for vault", config.oldKarakPTVault.name());

    //             uint256 ptBalanceBefore = config.oldPT.balanceOf(address(config.oldKarakPTVault));
    //             uint256 underlyingBalanceBefore = config.underlying.balanceOf(address(config.oldKarakPTVault));
    //             console2.log("PT Balance Before", ptBalanceBefore);
    //             console2.log("Underlying Balance Before", underlyingBalanceBefore);

    //             assertGt(ptBalanceBefore, 0);
    //             assertEq(underlyingBalanceBefore, 0);

    //             startTx(vaultSupervisor.owner());
    //             vaultSupervisor.vaultSwap(
    //                 config.oldKarakPTVault,
    //                 IVault.SwapAssetParams({
    //                     newDepositToken: config.underlying,
    //                     name: config.karakVaultSwapName,
    //                     symbol: config.karakVaultSwapSymbol,
    //                     assetType: IVault.AssetType.ETH,
    //                     assetLimit: config.oldKarakPTVault.assetLimit() // TODO(Drew): Update this if you want
    //                 }),
    //                 config.minUnderlyingAmount,
    //                 bytes("")
    //             );
    //             stopTx();

    //             uint256 ptBalanceAfter = config.oldPT.balanceOf(address(config.oldKarakPTVault));
    //             uint256 underlyingBalanceAfter = config.underlying.balanceOf(address(config.oldKarakPTVault));
    //             console2.log("PT Balance After", ptBalanceAfter);
    //             console2.log("Underlying Balance After", underlyingBalanceAfter);

    //             assertEq(ptBalanceAfter, 0);
    //             assertGt(underlyingBalanceAfter, 0);

    //             console2.log();
    //         }

    //         // Reset array to prevent config leak between chains
    //         delete rolloverConfigs;
    //     }
    // }

    function test_user_migrate() public {
        for (uint256 i = 0; i < runForChains.length; i++) {
            setUpForChain(runForChains[i]);
            for (uint256 i = 0; i < rolloverConfigs.length; i++) {
                PTRolloverConfig memory config = rolloverConfigs[i];
                if (!config.initialized || config.testUser == address(0)) continue; //need to revert this

                console2.log("Testing user migrate for", config.karakVaultSwapName);

                address user = config.testUser;

                // Get user's current position in old vault
                (IVault[] memory userVaults,,, uint256[] memory userShares) = vaultSupervisor.getDeposits(user);
                uint256 oldShares = 0;
                for (uint256 j = 0; j < userVaults.length; j++) {
                    if (address(userVaults[j]) == address(config.oldKarakPTVault)) {
                        oldShares = userShares[j];
                        break;
                    }
                }
                require(oldShares > 0, "Test user has no shares in old vault");

                uint256 oldAssetsToMigrate = config.oldKarakPTVault.convertToAssets(oldShares);
                uint256 minNewAssets = oldAssetsToMigrate * 99 / 100; // 1% slippage tolerance - for now assume price is 1:1 old:new - TODO: Update this value after observing test logs
                uint256 minNewShares = config.newKarakPTVault.convertToShares(minNewAssets);

                uint256 minYTAmount = 1; // Minimum YT to be minted - TODO: Update this value after observing test logs
                bytes memory swapperOtherParams = abi.encode(user, minYTAmount);

                // Execute migration
                vm.prank(user);
                vaultSupervisor.migrate(
                    config.oldKarakPTVault, config.newKarakPTVault, oldShares, minNewShares, swapperOtherParams
                );

                // Verify results
                (userVaults,,, userShares) = vaultSupervisor.getDeposits(user);

                bool foundNewVault = false;
                uint256 newShares = 0;
                for (uint256 j = 0; j < userVaults.length; j++) {
                    if (address(userVaults[j]) == address(config.newKarakPTVault)) {
                        foundNewVault = true;
                        newShares = userShares[j];
                        break;
                    }
                }

                assertTrue(foundNewVault, "User should have the new vault after migration");
                assertGt(newShares, 0, "User should have shares in the new vault");

                uint256 ytBalance = config.newYT.balanceOf(user);
                assertGe(ytBalance, minYTAmount, "User should have received at least the minimum YT amount");

                console2.log("Old shares:", oldShares);
                console2.log("New shares:", newShares);
                console2.log("YT balance:", ytBalance);
                console2.log();
            }
        }
    }

    function setUpForChain(PTRolloverChainConfig.Chain chain) public {
        PTRolloverChainConfig.ChainAddresses memory chainAddresses =
            PTRolloverChainConfig.getChainAddresses(currentChain);

        vaultSupervisor = VaultSupervisor(chainAddresses.VAULT_SUPERVISOR);

        if (currentChain == PTRolloverChainConfig.Chain.Mainnet) {
            chainName = "mainnet";
            currentForkUrl = vm.envString("MAINNET_RPC_URL");
            pinToBlock = 20167124;
            warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        } else if (currentChain == PTRolloverChainConfig.Chain.Arbitrum) {
            chainName = "arbitrum";
            currentForkUrl = vm.envString("ARBITRUM_RPC_URL");
            pinToBlock = 225506952;
            warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        }

        currentFork = vm.createFork(currentForkUrl);
        vm.selectFork(currentFork);

        if (pinToBlock > 0) {
            vm.rollFork(pinToBlock);
        }

        if (warpToTimestamp > 0) {
            vm.warp(warpToTimestamp);
        }

        console2.log("Current chain:", chainName);
        console2.log("Current fork:", currentFork);
        console2.log("Current fork URL:", currentForkUrl);
        console2.log("Pin to block:", pinToBlock);
        console2.log("Warp to timestamp:", warpToTimestamp);
        console2.log();

        // Upgrade the VaultSupervisor to enable new swap and migrate functionality
        upgradeVaultSupervisor(ERC1967Factory(chainAddresses.ERC1967_FACTORY), address(chainAddresses.VAULT_SUPERVISOR));

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

        pendleSwapper = setupPendleSwapper(rolloverConfigs, chainAddresses.PENDLE_ROUTER_V4);
    }

    function setupRolloverConfigs() internal returns (PTRolloverConfig[] memory configs) {
        PTRolloverChainConfig.AssetConfig[] memory chainAssets = PTRolloverChainConfig.getChainAssets(currentChain);

        for (uint256 i = 0; i < chainAssets.length; i++) {
            PTRolloverChainConfig.AssetConfig memory assetConfig = chainAssets[i];

            PTRolloverConfig memory config = createRolloverConfig(
                assetConfig.addresses.underlying,
                assetConfig.addresses.oldPT,
                assetConfig.addresses.oldYT,
                assetConfig.addresses.newPT,
                assetConfig.addresses.newYT,
                assetConfig.addresses.oldKarakPTVault,
                assetConfig.addresses.newKarakPTVault,
                string(abi.encodePacked("Karak PT ", assetConfig.name, " NEXT")),
                string(abi.encodePacked("K-PT-", assetConfig.name, "-NEXT")),
                IVault.AssetType.ETH,
                assetConfig.karakVaultSwapName,
                assetConfig.karakVaultSwapSymbol,
                assetConfig.minUnderlyingAmount,
                assetConfig.testUser
            );

            if (config.initialized) {
                rolloverConfigs.push(config);
            }
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
        string memory karakVaultSwapName,
        string memory karakVaultSwapSymbol,
        uint256 minUnderlyingAmount,
        address testUser
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
                karakVaultSwapName: karakVaultSwapName,
                karakVaultSwapSymbol: karakVaultSwapSymbol,
                minUnderlyingAmount: minUnderlyingAmount,
                testUser: testUser
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

    function setupPendleSwapper(PTRolloverConfig[] storage configs, address pendleRouter)
        internal
        returns (PendleSwapper pendleSwapper)
    {
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
        pendleSwapper = new PendleSwapper(owner, IPendleRouter(pendleRouter));
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
