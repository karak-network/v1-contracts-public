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
import "solady/src/utils/ERC1967Factory.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import "forge-std/console.sol";

struct VaultData {
    uint8 assetType;
    string name;
    string symbol;
    address token;
    uint256 initialDeposit;
}

struct VaultDataList {
    address multisig;
    VaultData[] vaultData;
}

contract KarakRestaking is Script {
    string constant DEPLOYMENT_FILE_NAME = "ethereum_mainnet_data";

    // Numerical Constants
    uint256 internal constant WITHDRAW_DELAY = 14 days;
    uint256 internal constant TIMELOCK_DELAY = 2 days;
    uint256 internal constant INITIAL_GLOBAL_USD_LIMIT = 60_000_000 * 1e18;
    uint256 internal constant INITIAL_ETH_PRICE = 3400;
    uint256 internal constant INITIAL_BTC_PRICE = 70000;
    uint256 internal constant INITIAL_VAULT_LIMIT = type(uint256).max;

    // Addresses
    address internal constant DEPLOYER = 0x169438698266B07Fc76300aC6F09e0dc32181FD9; // deploys all the contracts and does initial setup
    address internal constant MANAGER = 0x169438698266B07Fc76300aC6F09e0dc32181FD9; // can run day-to-day operations
    //address internal constant TIMELOCK_OWNER = 0x58c56C901460c3Aa7Bda6A76cB3a795945089E45; // usually multisig

    address internal constant OWNER = address(1); // TODO;
    // address internal constant MANAGER = address(2); // TODO;

    VaultDataList vaultDataList;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/VaultData/", DEPLOYMENT_FILE_NAME, ".json");
        string memory file = vm.readFile(path);
        bytes memory parsed = vm.parseJson(file);
        vaultDataList = abi.decode(parsed, (VaultDataList));
    }

    function run() public {
        validateConfig();

        vm.startBroadcast();
        //address timelockOwner = vaultDataList.multisig;
        address timelockOwner = MANAGER;
        address timelock = MANAGER;
        //address timelock = deployTimelock(timelockOwner, MANAGER, TIMELOCK_DELAY);
        address proxyAdmin = timelock;

        ILimiter limiter = ILimiter(new Limiter(INITIAL_ETH_PRICE, INITIAL_BTC_PRICE, INITIAL_GLOBAL_USD_LIMIT));
        (address vaultImpl, address vaultSupervisorImpl, address delegationSupervisorImpl) = deployImplementations();

        ERC1967Factory factory = new ERC1967Factory();

        VaultSupervisor vaultSupervisor = VaultSupervisor(factory.deploy(vaultSupervisorImpl, proxyAdmin));

        DelegationSupervisor delegationSupervisor =
            DelegationSupervisor(factory.deploy(delegationSupervisorImpl, proxyAdmin));

        IQuerier querier = IQuerier(new Querier(address(vaultSupervisor), address(delegationSupervisor)));

        vaultSupervisor.initialize(address(delegationSupervisor), vaultImpl, limiter, MANAGER);
        delegationSupervisor.initialize(address(vaultSupervisor), WITHDRAW_DELAY, MANAGER);

        for (uint256 i = 0; i < vaultDataList.vaultData.length; i++) {
            IVault vault = vaultSupervisor.deployVault(
                IERC20(vaultDataList.vaultData[i].token),
                vaultDataList.vaultData[i].name,
                vaultDataList.vaultData[i].symbol,
                IVault.AssetType(vaultDataList.vaultData[i].assetType)
            );
            vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, INITIAL_VAULT_LIMIT));
            console.log("vault ", vaultDataList.vaultData[i].name, ": ", address(vault));
            uint256 initialDeposit = vaultDataList.vaultData[i].initialDeposit;
            console.log("Initial deposit of ", initialDeposit);
            IERC20(vaultDataList.vaultData[i].token).approve(address(vault), initialDeposit);
            vaultSupervisor.deposit(vault, initialDeposit, initialDeposit);
        }

        // Transfer ownership to the timelock
        //vaultSupervisor.transferOwnership(timelock);
        vm.stopBroadcast();

        console.log("Vault Impl:", address(vaultImpl));
        console.log("Vault Supervisor:", address(vaultSupervisor));
        console.log("Delegation Supervisor:", address(delegationSupervisor));
        console.log("Querier:", address(querier));
        console.log("Factory:", address(factory));
        console.log("Limiter:", address(limiter));
        console.log("Timelock:", timelock);
        console.log("Timelock Owner:", timelockOwner);
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
        require(uint160(vaultDataList.multisig) > 100, "MULTISIG IS NOT SET");
        require(uint160(MANAGER) > 100, "MANAGER IS NOT SET");
        require(INITIAL_ETH_PRICE > 1000, "INITIAL_ETH_PRICE SEEMS NOT SET");
        require(INITIAL_GLOBAL_USD_LIMIT > 1000 * 1e18, "INITIAL_USD_LIMIT SEEMS NOT SET");
    }

    function deployTimelock(address multisig, address assistant, uint256 delay) internal returns (address timelock) {
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](2);
        executors[0] = multisig;
        executors[1] = assistant;
        TimelockController _timelock = new TimelockController(delay, proposers, executors, assistant);
        return address(_timelock);
        //return(address(1));
    }
}
