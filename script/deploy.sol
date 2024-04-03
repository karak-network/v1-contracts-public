// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {VaultSupervisor} from "../src/VaultSupervisor.sol";
import {DelegationSupervisor} from "../src/DelegationSupervisor.sol";
import {Querier} from "../src/Querier.sol";
import {Limiter} from "../src/Limiter.sol";
import {IQuerier} from "../src/interfaces/IQuerier.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {ILimiter} from "../src/interfaces/ILimiter.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "solady/src/utils/ERC1967Factory.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "forge-std/console.sol";

struct VaultData {
    uint8 assetType;
    string name;
    string symbol;
    address token;
}

struct VaultDataList {
    VaultData[] vaultData;
}

contract KarakRestaking is Script {
    uint256 internal constant WITHDRAW_DELAY = 86400;

    uint256 internal constant INITIAL_USD_LIMIT = 100_000_000 * 1e18;
    uint256 internal constant INITIAL_ETH_PRICE = 3600;
    address internal constant OWNER = address(1); // TODO;
    address internal constant MANAGER = address(2); // TODO;

    VaultDataList vaultDataList;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory filename = "ethereum_mainnet_data";
        string memory path = string.concat(root, "/script/VaultData/", filename, ".json");
        string memory file = vm.readFile(path);
        bytes memory parsed = vm.parseJson(file);
        vaultDataList = abi.decode(parsed, (VaultDataList));
    }

    function run() public {
        validateConfig();

        vm.startBroadcast();
        address proxyAdmin = address(msg.sender);

        ILimiter limiter = ILimiter(new Limiter(INITIAL_ETH_PRICE, INITIAL_USD_LIMIT));
        (address vaultImpl, address vaultSupervisorImpl, address delegationSupervisorImpl) = deployImplementations();
        ERC1967Factory factory = new ERC1967Factory();
        VaultSupervisor vaultSupervisor = VaultSupervisor(factory.deploy(vaultSupervisorImpl, proxyAdmin));
        DelegationSupervisor delegationSupervisor =
            DelegationSupervisor(factory.deploy(delegationSupervisorImpl, proxyAdmin));
        IQuerier querier = IQuerier(new Querier(address(vaultSupervisor), address(delegationSupervisor)));
        vaultSupervisor.initialize(address(delegationSupervisor), vaultImpl, limiter, MANAGER);
        delegationSupervisor.initialize(address(vaultSupervisor), WITHDRAW_DELAY, MANAGER);

        console.log("Vault Supervisor:", address(vaultSupervisor));
        console.log("Delegation Supervisor:", address(delegationSupervisor));
        console.log("Querier:", address(querier));
        console.log("factory:", address(factory));
        for (uint256 i = 0; i < vaultDataList.vaultData.length; i++) {
            IVault vault = vaultSupervisor.deployVault(
                IERC20(vaultDataList.vaultData[i].token),
                vaultDataList.vaultData[i].name,
                vaultDataList.vaultData[i].symbol,
                IVault.AssetType(vaultDataList.vaultData[i].assetType)
            );
            vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, 1000 ether));
            console.log("vault ", vaultDataList.vaultData[i].name, ": ", address(vault));
        }
        vm.stopBroadcast();
    }

    function deployImplementations()
        internal
        returns (address vaultImpl, address vaultSupervisorImpl, address delegationSupervisorImpl)
    {
        vaultImpl = address(new Vault());
        vaultSupervisorImpl = address(new VaultSupervisor());
        delegationSupervisorImpl = address(new DelegationSupervisor());
        return (vaultImpl, vaultSupervisorImpl, delegationSupervisorImpl);
    }

    function validateConfig() internal view {
        require(uint160(OWNER) > 100, "OWNER IS NOT SET");
        require(uint160(MANAGER) > 100, "MANAGER IS NOT SET");
        require(INITIAL_ETH_PRICE > 1000, "INITIAL_ETH_PRICE SEEMS NOT SET");
        require(INITIAL_USD_LIMIT > 1000 * 1e18, "INITIAL_USD_LIMIT SEEMS NOT SET");
    }
}
