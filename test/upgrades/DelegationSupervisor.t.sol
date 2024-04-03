pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import "solady/src/utils/ERC1967Factory.sol";

import "../utils/ERC20Mintable.sol";
import "../../src/Vault.sol";
import "../../src/VaultSupervisor.sol";
import "../../src/DelegationSupervisor.sol";
import "../../src/interfaces/Errors.sol";

contract DelegationSupervisorUpgradeTest is Test {
    Vault vault;
    VaultSupervisor vaultSupervisor;
    DelegationSupervisor delegationSupervisor;
    ERC20Mintable depositToken;
    ERC1967Factory factory;

    address proxyAdmin = address(2);
    ILimiter limiter = ILimiter(address(3));
    address manager = address(12);

    function setUp() public {
        address delegationSupervisorImpl = address(new DelegationSupervisor());
        address vaultImpl = address(new Vault());
        factory = new ERC1967Factory();
        vaultSupervisor = VaultSupervisor(factory.deploy(address(new VaultSupervisor()), proxyAdmin));

        delegationSupervisor = DelegationSupervisor(factory.deploy(delegationSupervisorImpl, proxyAdmin));

        vaultSupervisor.initialize(address(delegationSupervisor), vaultImpl, limiter, manager);
        delegationSupervisor.initialize(address(vaultSupervisor), 10, manager);

        depositToken = new ERC20Mintable();
        vm.prank(manager);
        vault = Vault(
            address(vaultSupervisor.deployVault(IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH))
        );
    }

    function test_upgrade_not_admin() public {
        address newDelegationSupervisorImpl = address(new DelegationSupervisor());

        vm.expectRevert(ERC1967Factory.Unauthorized.selector);
        factory.upgrade(address(delegationSupervisor), newDelegationSupervisorImpl);
    }

    function test_upgrade() public {
        bytes32 oldImplBytes32 =
            vm.load(address(delegationSupervisor), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        oldImplBytes32 = oldImplBytes32 << 96;

        address newDelegationSupervisorImpl = address(new DelegationSupervisor());

        vm.prank(proxyAdmin);
        factory.upgrade(address(delegationSupervisor), newDelegationSupervisorImpl);

        bytes32 readImplBytes32 =
            vm.load(address(delegationSupervisor), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc);
        readImplBytes32 = readImplBytes32 << 96;

        assertEq(readImplBytes32, bytes32(bytes20(newDelegationSupervisorImpl)));
        assertNotEq(readImplBytes32, oldImplBytes32);
    }
}
