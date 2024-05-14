// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {VaultSupervisor} from "../src/VaultSupervisor.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "forge-std/console.sol";

struct VaultData {
    uint8 assetType;
    string name;
    string symbol;
    address token;
}

struct VaultDataList {
    address multiSig;
    VaultData[] vaultData;
    address vaultSupervisor;
}

contract DeployExtraVaults is Script {
    VaultDataList vaultDataList;

    function setUp() public {
        string memory root = vm.projectRoot();
        string memory filename = "ethereum_mainnet_extra_vault";
        string memory path = string.concat(root, "/script/VaultData/", filename, ".json");
        string memory file = vm.readFile(path);
        bytes memory parsed = vm.parseJson(file);
        vaultDataList = abi.decode(parsed, (VaultDataList));
    }

    function run() public {
        vm.startBroadcast();
        VaultSupervisor vaultSupervisor = VaultSupervisor(vaultDataList.vaultSupervisor);

        for (uint256 i = 0; i < vaultDataList.vaultData.length; i++) {
            VaultData memory vaultConfig = vaultDataList.vaultData[i];
            IVault vault = vaultSupervisor.deployVault(
                IERC20(vaultConfig.token), vaultConfig.name, vaultConfig.symbol, IVault.AssetType(vaultConfig.assetType)
            );
            vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, 100_000_000 ether));
            console.log("vault ", vaultConfig.name, ": ", address(vault));
        }
        vm.stopBroadcast();
    }
}
