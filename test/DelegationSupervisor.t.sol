// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import "solady/src/auth/OwnableRoles.sol";

import "../src/Vault.sol";
import "../src/Limiter.sol";
import "../src/interfaces/IVaultSupervisor.sol";
import "../src/interfaces/IDelegationSupervisor.sol";
import "../src/VaultSupervisor.sol";
import "../src/DelegationSupervisor.sol";
import "../src/interfaces/ILimiter.sol";
import "./utils/ERC20Mintable.sol";
import "./utils/ProxyDeployment.sol";
import "../src/interfaces/Errors.sol";

contract DelegationSupervisorTest is Test {
    IVault vault;
    IVaultSupervisor vaultSupervisor;
    DelegationSupervisor delegationSupervisor;
    address owner = address(7);
    ERC20Mintable depositToken;
    address operatorRewards = address(3);
    address proxyAdmin = address(11);
    ILimiter limiter;
    address manager = address(12);

    function setUp() public {
        address vaultImpl = address(new Vault());
        vaultSupervisor = IVaultSupervisor(ProxyDeployment.factoryDeploy(address(new VaultSupervisor()), proxyAdmin));
        limiter = ILimiter(new Limiter(1, type(uint256).max));
        delegationSupervisor =
            DelegationSupervisor(ProxyDeployment.factoryDeploy(address(new DelegationSupervisor()), proxyAdmin));

        vm.prank(owner);
        vaultSupervisor.initialize(address(delegationSupervisor), vaultImpl, limiter, manager);

        depositToken = new ERC20Mintable();

        vm.prank(manager);
        vault = vaultSupervisor.deployVault(IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH);
        vm.prank(owner);
        vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, 1000));

        vm.prank(owner);
        delegationSupervisor.initialize(address(vaultSupervisor), 10, manager);
        //delegationSupervisor.register(operatorConfig, "");

        depositToken.mint(address(this), 2000);
        depositToken.approve(address(vault), 1000);
        vaultSupervisor.deposit(IVault(address(vault)), 1000);
    }

    function started_withdraw_fixture() internal returns (Withdraw.QueuedWithdrawal[] memory) {
        IVault[] memory vaults = new IVault[](1);
        vaults[0] = IVault(address(vault));
        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;
        Withdraw.WithdrawRequest[] memory queuedConfig = new Withdraw.WithdrawRequest[](1);
        queuedConfig[0] = Withdraw.WithdrawRequest({vaults: vaults, shares: shares, withdrawer: address(this)});
        (bytes32[] memory withdrawalRoots, Withdraw.QueuedWithdrawal[] memory withdrawConfigs) =
            delegationSupervisor.startWithdraw(queuedConfig);

        return (withdrawConfigs);
    }

    function test_not_enough_time_passed() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture();

        vm.expectRevert(MinWithdrawDelayNotPassed.selector);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
    }

    function test_paused() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture();

        vm.warp(1000);

        vm.prank(manager);
        delegationSupervisor.pause(true);

        vm.expectRevert(Ownable.Unauthorized.selector);
        delegationSupervisor.pause(false);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
    }

    function test_withdraw() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture();

        assertEq(
            keccak256(abi.encode(delegationSupervisor.fetchQueuedWithdrawals(address(this)))),
            keccak256(abi.encode(withdrawConfigs))
        );
        assertTrue(delegationSupervisor.isWithdrawPending(withdrawConfigs[0]));
        vm.warp(1000);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
        assertFalse(delegationSupervisor.isWithdrawPending(withdrawConfigs[0]));
    }

    function test_update_configs() public {
        vm.prank(manager);
        delegationSupervisor.updateMinWithdrawDelay(1001);
        assertEq(delegationSupervisor.withdrawalDelay(), 1001);

        vm.expectRevert(Ownable.Unauthorized.selector);
        delegationSupervisor.updateMinWithdrawDelay(1001);
    }

    function test_Add_manager() public {
        address newManager = address(19);
        vm.startPrank(owner);

        OwnableRoles(address(delegationSupervisor)).grantRoles(newManager, Constants.MANAGER_ROLE);
        assertTrue(OwnableRoles(address(delegationSupervisor)).hasAllRoles(newManager, Constants.MANAGER_ROLE));
        assertFalse(OwnableRoles(address(delegationSupervisor)).hasAllRoles(address(18), Constants.MANAGER_ROLE));
    }
}
