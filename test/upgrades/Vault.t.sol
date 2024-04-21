pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import "solady/src/auth/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import "../../src/Vault.sol";
import "../../src/Limiter.sol";
import "../../src/interfaces/ILimiter.sol";
import "../../src/VaultSupervisor.sol";
import "../utils/ERC20Mintable.sol";
import "../../src/interfaces/Errors.sol";
import "../utils/ProxyDeployment.sol";

contract VaultUpgradeTest is Test {
    IVault vault;
    VaultSupervisor vaultSupervisor;
    ERC20Mintable depositToken;
    address delegationSupervisor = address(1);
    address proxyAdmin = address(11);
    ILimiter limiter;
    address manager = address(12);

    function setUp() public {
        vaultSupervisor = VaultSupervisor(ProxyDeployment.factoryDeploy(address(new VaultSupervisor()), proxyAdmin));
    }

    function setupFixture() internal {
        address vaultImpl = address(new Vault());
        limiter = ILimiter(new Limiter(1, 1, type(uint256).max));
        vaultSupervisor.initialize(delegationSupervisor, vaultImpl, limiter, manager);
        depositToken = new ERC20Mintable();
        depositToken.initialize("Test", "TST", 18);

        vm.prank(manager);
        vault = vaultSupervisor.deployVault(IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH);

        vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, 1000));
    }

    function flowFixture() internal {
        // Deposit
        depositToken.mint(address(this), 2000);
        depositToken.approve(address(vault), 2000);
        uint256 shares = vaultSupervisor.deposit(IVault(address(vault)), 1000, 1000);
        assertEq(shares, 1000);
        assertEq(depositToken.balanceOf(address(this)), 1000);
        vm.prank(delegationSupervisor);
        vaultSupervisor.redeemShares(address(this), IVault(address(vault)), 1000);
        assertEq(depositToken.balanceOf(address(this)), 2000);
    }

    function test_fail_not_owner() public {
        setupFixture();
        Vault newImpl = new Vault();

        vm.startPrank(manager);
        vm.expectRevert(Ownable.Unauthorized.selector);
        vaultSupervisor.changeImplementation(address(newImpl));

        vm.expectRevert(Ownable.Unauthorized.selector);
        vaultSupervisor.changeImplementationForVault(address(vault), address(newImpl));
    }

    function test_upgrade_all() public {
        setupFixture();
        address oldImpl = vaultSupervisor.implementation();
        Vault newImpl = Vault(address(new Vault()));
        vaultSupervisor.changeImplementation(address(newImpl));

        address newImplRes = vaultSupervisor.implementation();

        assertNotEq(oldImpl, address(newImplRes));
        assertEq(newImplRes, address(newImpl));

        // Try depositing with new implementation
        flowFixture();
    }

    function test_upgrade_single() public {
        setupFixture();
        address oldImpl = vaultSupervisor.implementation();
        Vault newImpl = Vault(address(new Vault()));
        vaultSupervisor.changeImplementationForVault(address(vault), address(newImpl));

        address newImplRes = vaultSupervisor.implementation(address(vault));
        address globalImpl = vaultSupervisor.implementation();

        assertNotEq(oldImpl, address(newImplRes));
        assertNotEq(newImplRes, globalImpl);
        assertEq(newImplRes, address(newImpl));

        // Try dpeositing with new implementation
        flowFixture();
    }
}
