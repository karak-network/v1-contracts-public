// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IVault2} from "../../src/interfaces/IVault2.sol";
import {Vault} from "../../src/Vault.sol";
import {ERC1967Factory} from "solady/src/utils/ERC1967Factory.sol";
import {VaultSupervisor, ILimiter} from "../../src/VaultSupervisor.sol";
import {V2MigrationChainConfig} from "../../script/config/V2MigrationConfig.sol";
import "../../src/interfaces/Errors.sol";
import "./Vault2.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "../utils/ERC20Mintable.sol";

import "../utils/ProxyDeployment.sol";

contract V2Migration is Test, Script {
    using V2MigrationChainConfig for V2MigrationChainConfig.ChainConfig;

    struct ChainForkMetadata {
        V2MigrationChainConfig.ChainAddresses chainAddresses;
        uint256 forkId;
        string chainName;
        string rpcURL;
        uint256 currentFork;
        uint256 pinToBlock;
        uint256 warpToTimestamp;
        address v1Vault;
        address v2Vault;
    }

    bool isScript = false;

    VaultSupervisor vaultSupervisor;

    V2MigrationChainConfig.Chain[] runForChains;
    mapping(V2MigrationChainConfig.Chain chain => ChainForkMetadata) chainToForkData;
    V2MigrationChainConfig.ChainConfig chainConfig;

    function setUp() public {
        runForChains = [
            V2MigrationChainConfig.Chain.Mainnet,
            V2MigrationChainConfig.Chain.Arbitrum,
            V2MigrationChainConfig.Chain.Blast,
            V2MigrationChainConfig.Chain.BSC,
            V2MigrationChainConfig.Chain.Karak,
            V2MigrationChainConfig.Chain.Mantle
        ];
        chainConfig.initialize();
        for (uint256 i = 0; i < runForChains.length; i++) {
            ChainForkMetadata memory chainData = setUpForkForChain(runForChains[i]);
            // Upgrade the VaultSupervisor to enable new swap and migrate functionality
            upgradeVaultSupervisor(
                ERC1967Factory(chainData.chainAddresses.ERC1967_FACTORY),
                address(chainData.chainAddresses.VAULT_SUPERVISOR)
            );
            chainToForkData[runForChains[i]] = chainData;
        }
    }

    function run() public {
        isScript = true;
    }

    function test_asset_migration(uint256 depositAmount, uint256 migrationAmount) public {
        address user = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;
        vm.assume(depositAmount > 0 && depositAmount < UINT256_MAX / 2);
        if (migrationAmount > depositAmount || migrationAmount == 0) return;

        for (uint256 i = 0; i < runForChains.length; i++) {
            V2MigrationChainConfig.Chain chain = runForChains[i];
            vm.selectFork(chainToForkData[chain].forkId);
            console2.log("Current chain: ", chainToForkData[chain].chainName);
            console2.log("Current fork:", chainToForkData[chain].forkId);
            console2.log("Current fork URL:", chainToForkData[chain].rpcURL);
            console2.log("Pin to block:", chainToForkData[chain].pinToBlock);
            console2.log("Warp to timestamp:", chainToForkData[chain].warpToTimestamp);

            vaultSupervisor = VaultSupervisor(chainToForkData[chain].chainAddresses.VAULT_SUPERVISOR);
            IVault vault1 = IVault(chainToForkData[chain].v1Vault);
            address vault2 = chainToForkData[chain].v2Vault;

            console2.log("Vault1: ", address(vault1));
            console2.log("Vault2: ", vault2);

            if (!isScript) {
                deposit(depositAmount, vault1, user);
            }

            uint256 initialDeposit = _getVaultDeposit(user, vault1);
            console2.log("Initial deposit:", initialDeposit);
            console2.log("Migration amount:", migrationAmount);
            console2.log();
            startTx(user);
            migrateAssets(vault1, vault2, migrationAmount, migrationAmount);
            assertEq(IERC20(vault2).balanceOf(user), migrationAmount);
            assertEq(_getVaultDeposit(user, vault1), initialDeposit - migrationAmount);
            stopTx();
        }
    }

    function test_fail_not_enough_shares_minted_at_v2(uint256 depositAmount, uint256 migrationAmount) public {
        address user = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;
        vm.assume(depositAmount > 0 && depositAmount < UINT256_MAX / 2);
        if (migrationAmount > depositAmount || migrationAmount == 0) return;

        for (uint256 i = 0; i < runForChains.length; i++) {
            V2MigrationChainConfig.Chain chain = runForChains[i];
            vm.selectFork(chainToForkData[chain].forkId);
            console2.log("Current chain: ", chainToForkData[chain].chainName);
            console2.log("Current fork:", chainToForkData[chain].forkId);
            console2.log("Current fork URL:", chainToForkData[chain].rpcURL);
            console2.log("Pin to block:", chainToForkData[chain].pinToBlock);
            console2.log("Warp to timestamp:", chainToForkData[chain].warpToTimestamp);

            vaultSupervisor = VaultSupervisor(chainToForkData[chain].chainAddresses.VAULT_SUPERVISOR);
            IVault vault1 = IVault(chainToForkData[chain].v1Vault);
            address vault2 = chainToForkData[chain].v2Vault;

            console2.log("Vault1: ", address(vault1));
            console2.log("Vault2: ", vault2);
            console2.log();

            if (!isScript) {
                deposit(depositAmount, vault1, user);
            }

            startTx(user);
            // No shares are minted at v2
            console2.log("Mock call setup for vault2 deposit.");
            vm.mockCall(
                vault2,
                abi.encodeWithSelector(Vault2.deposit.selector, migrationAmount, user, migrationAmount),
                abi.encode(migrationAmount + 1)
            );
            vm.expectRevert(NotEnoughShares.selector);
            migrateAssets(vault1, vault2, migrationAmount, migrationAmount);
            stopTx();
        }
    }

    function test_fail_migrate_more_assets_than_balance(uint256 depositAmount, uint256 migrationAmount) public {
        address user = 0x54603E6fd3A92E32Bd3c00399D306B82bB3601Ba;
        vm.assume(depositAmount < UINT256_MAX / 2);
        if (migrationAmount <= depositAmount || migrationAmount == 0) return;

        for (uint256 i = 0; i < runForChains.length; i++) {
            V2MigrationChainConfig.Chain chain = runForChains[i];
            vm.selectFork(chainToForkData[chain].forkId);
            console2.log("Current chain: ", chainToForkData[chain].chainName);
            console2.log("Current fork:", chainToForkData[chain].forkId);
            console2.log("Current fork URL:", chainToForkData[chain].rpcURL);
            console2.log("Pin to block:", chainToForkData[chain].pinToBlock);
            console2.log("Warp to timestamp:", chainToForkData[chain].warpToTimestamp);

            vaultSupervisor = VaultSupervisor(chainToForkData[chain].chainAddresses.VAULT_SUPERVISOR);
            IVault vault1 = IVault(chainToForkData[chain].v1Vault);
            address vault2 = chainToForkData[chain].v2Vault;

            console2.log("Vault1: ", address(vault1));
            console2.log("Vault2: ", vault2);
            console2.log("Expected revert due to migration of more assets than balance.");
            console2.log();

            if (!isScript) {
                deposit(depositAmount, vault1, user);
            }

            startTx(user);
            vm.expectRevert(NotEnoughShares.selector);
            migrateAssets(vault1, vault2, migrationAmount, migrationAmount);
            stopTx();
        }
    }

    function _getVaultDeposit(address user, IVault vault) internal view returns (uint256) {
        (IVault[] memory vaults,,, uint256[] memory shares) = vaultSupervisor.getDeposits(user);
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == vault) return shares[i];
        }
        return 0;
    }

    function deposit(uint256 amount, IVault vault, address user) internal {
        if (amount == 0) return;
        ERC20Mintable(vault.asset()).mint(user, amount);
        address owner = vaultSupervisor.owner();
        vm.prank(owner);
        // Remove limiter in test as no deposits will there in vaultSupervisor v1
        vaultSupervisor.setLimiter(ILimiter(address(0)));

        startTx(user);
        IERC20(vault.asset()).approve(address(vault), amount);
        vaultSupervisor.deposit(vault, amount, amount);
        stopTx();
    }

    function setUpForkForChain(V2MigrationChainConfig.Chain chain)
        internal
        returns (ChainForkMetadata memory chainData)
    {
        chainData.chainAddresses = chainConfig.getChainAddresses(chain);

        vaultSupervisor = VaultSupervisor(chainData.chainAddresses.VAULT_SUPERVISOR);
        if (chain == V2MigrationChainConfig.Chain.Mainnet) {
            chainData.chainName = "mainnet";
            chainData.rpcURL = vm.envString("MAINNET_RPC_URL");
            chainData.pinToBlock = 20167124;
            chainData.warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        } else if (chain == V2MigrationChainConfig.Chain.Arbitrum) {
            chainData.chainName = "arbitrum";
            chainData.rpcURL = vm.envString("ARBITRUM_RPC_URL");
            chainData.pinToBlock = 225506952;
            chainData.warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        } else if (chain == V2MigrationChainConfig.Chain.Karak) {
            chainData.chainName = "karak";
            chainData.rpcURL = vm.envString("KARAK_RPC_URL");
            chainData.pinToBlock = 4450940;
            chainData.warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        } else if (chain == V2MigrationChainConfig.Chain.Mantle) {
            chainData.chainName = "mantle";
            chainData.rpcURL = vm.envString("MANTLE_RPC_URL");
            chainData.pinToBlock = 62682580;
            chainData.warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        } else if (chain == V2MigrationChainConfig.Chain.BSC) {
            chainData.chainName = "bsc";
            chainData.rpcURL = vm.envString("BSC_RPC_URL");
            chainData.pinToBlock = 39498130;
            chainData.warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        } else if (chain == V2MigrationChainConfig.Chain.Blast) {
            chainData.chainName = "blast";
            chainData.rpcURL = vm.envString("BLAST_RPC_URL");
            chainData.pinToBlock = 5287690;
            chainData.warpToTimestamp = 1719547840; // Fri Jun 28 2024 04:10:40 GMT+0000
        }

        chainData.forkId = vm.createFork(chainData.rpcURL);
        vm.selectFork(chainData.forkId);
        console2.log("Forking chain:", chainData.chainName);
        console2.log();

        startTx(address(this));
        ERC20Mintable depositToken = new ERC20Mintable();
        depositToken.initialize("V1TestToken", "V1Token", 8);
        stopTx();

        chainData.v1Vault =
            address(deployNewVault(IERC20(address(depositToken)), "V1-Vault", "V1V", IVault.AssetType.STABLE));

        chainData.v2Vault =
            address(deployNewV2Vault(IERC20(address(depositToken)), "V2-Vault", "V2V", IVault.AssetType.STABLE));
    }

    function deployNewVault(IERC20 depositToken, string memory name, string memory symbol, IVault.AssetType assetType)
        internal
        returns (IVault newVault)
    {
        address admin = vaultSupervisor.owner();
        startTx(admin);
        newVault = vaultSupervisor.deployVault(depositToken, name, symbol, assetType);
        bytes memory fn = abi.encodeWithSelector(IVault.setLimit.selector, UINT256_MAX);
        vaultSupervisor.runAdminOperation(newVault, fn);
        stopTx();
    }

    function deployNewV2Vault(IERC20 depositToken, string memory name, string memory symbol, IVault.AssetType assetType)
        internal
        returns (IVault newVault)
    {
        address admin = vaultSupervisor.owner();
        startTx(admin);
        newVault = vaultSupervisor.deployVault(depositToken, name, symbol, assetType);
        bytes memory fn = abi.encodeWithSelector(IVault.setLimit.selector, UINT256_MAX);
        vaultSupervisor.runAdminOperation(newVault, fn);
        vaultSupervisor.changeImplementationForVault(address(newVault), address(new Vault2()));
        stopTx();
    }

    function upgradeVaultSupervisor(ERC1967Factory factory, address proxy) internal {
        address proxyAdmin = factory.adminOf(proxy);

        startTx(proxyAdmin);
        address newVaultSupervisorImpl = address(new VaultSupervisor());
        factory.upgrade(proxy, newVaultSupervisorImpl);
        assertEq(newVaultSupervisorImpl, getImplementation(proxy));
        stopTx();
    }

    function migrateAssets(IVault v1Vault, address v2Vault, uint256 oldShares, uint256 minNewShares) internal {
        vaultSupervisor.migrateToV2(v1Vault, IVault2(v2Vault), oldShares, minNewShares);
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

    function getImplementation(address proxy) internal view returns (address) {
        bytes32 implValue = vm.load(proxy, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        return address(uint160(uint256(implValue)));
    }
}
