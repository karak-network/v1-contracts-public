pragma solidity ^0.8.21;

import "solady/src/utils/ERC1967Factory.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library ProxyDeployment {
    function factoryDeploy(address implementation, address proxyAdmin) public returns (address) {
        ERC1967Factory factory = new ERC1967Factory();
        return address(factory.deploy(implementation, proxyAdmin));
    }

    function deployTransparentUpgradeable(address implementation, address proxyAdmin) public returns (address) {
        return address(new TransparentUpgradeableProxy(implementation, proxyAdmin, bytes(abi.encode(""))));
    }
}
