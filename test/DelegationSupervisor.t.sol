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
        limiter = ILimiter(new Limiter(1, 1, type(uint256).max));
        delegationSupervisor =
            DelegationSupervisor(ProxyDeployment.factoryDeploy(address(new DelegationSupervisor()), proxyAdmin));

        vm.prank(owner);
        vaultSupervisor.initialize(address(delegationSupervisor), vaultImpl, limiter, manager);

        depositToken = new ERC20Mintable();

        vm.startPrank(owner);
        vault = vaultSupervisor.deployVault(IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH);
        vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, 5000));

        delegationSupervisor.initialize(address(vaultSupervisor), 10, manager);
        vm.stopPrank();
        //delegationSupervisor.register(operatorConfig, "");

        depositToken.mint(address(this), 2000);
        depositToken.approve(address(vault), 1000);
        vaultSupervisor.deposit(IVault(address(vault)), 1000, 1000);
    }

    function started_withdraw_fixture(uint256 withdrawShares, address transferTo)
        internal
        returns (Withdraw.QueuedWithdrawal[] memory)
    {
        IVault[] memory vaults = new IVault[](1);
        vaults[0] = IVault(address(vault));
        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawShares;
        Withdraw.WithdrawRequest[] memory queuedConfig = new Withdraw.WithdrawRequest[](1);
        queuedConfig[0] = Withdraw.WithdrawRequest({vaults: vaults, shares: shares, withdrawer: address(transferTo)});
        (bytes32[] memory withdrawalRoots, Withdraw.QueuedWithdrawal[] memory withdrawConfigs) =
            delegationSupervisor.startWithdraw(queuedConfig);

        return (withdrawConfigs);
    }

    function test_not_enough_time_passed() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture(1000, address(this));

        vm.expectRevert(MinWithdrawDelayNotPassed.selector);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
    }

    function test_paused() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture(1000, address(this));

        vm.warp(1000);

        vm.prank(manager);
        delegationSupervisor.pause(true);

        vm.expectRevert(Ownable.Unauthorized.selector);
        delegationSupervisor.pause(false);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
    }

    function test_withdraw() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture(1000, address(this));

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

    function test_updateMinWithdrawDelay(uint256 delay) public {
        vm.assume(delay < 30);
        vm.prank(owner);
        delegationSupervisor.updateMinWithdrawDelay(delay);
        uint256 withdrawDelay = delegationSupervisor.withdrawalDelay();

        assertEq(delay, withdrawDelay);
    }

    function test_updateMinWithdrawDelay_Unauthorized(uint256 delay) public {
        vm.assume(delay < 30);
        vm.expectRevert(Ownable.Unauthorized.selector);
        delegationSupervisor.updateMinWithdrawDelay(delay);
    }

    function test_fetchQueuedWithdrawals() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) =
            delegationSupervisor.fetchQueuedWithdrawals(address(this));

        assertEq(withdrawConfigs.length, 0);

        started_withdraw_fixture(300, address(this));
        started_withdraw_fixture(300, address(this));
        started_withdraw_fixture(300, address(this));

        withdrawConfigs = delegationSupervisor.fetchQueuedWithdrawals(address(this));
        assertEq(withdrawConfigs.length, 3);
    }

    function test_isWithdrawPending() public {
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture(1000, address(this));
        bool pending = delegationSupervisor.isWithdrawPending(withdrawConfigs[0]);
        assertEq(pending, true);

        vm.warp(1000);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
        pending = delegationSupervisor.isWithdrawPending(withdrawConfigs[0]);
        assertEq(pending, false);
        assertEq(depositToken.balanceOf(address(this)), 2000);
    }

    function test_withdrawal_with_yield(uint256 yield) public {
        vm.assume(yield < type(uint256).max - 1000);
        depositToken.mint(address(vault), yield);
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture(1000, address(this));
        vm.warp(1000);
        uint256 expectedAssets = vault.convertToAssets(1000);
        delegationSupervisor.finishWithdraw(withdrawConfigs);

        assertEq(depositToken.balanceOf(address(this)), 1000 + expectedAssets);
    }

    function test_e2e_deposit_withdraw(uint256 amount) public {
        vm.assume(amount > 1000);
        vm.assume(amount < (type(uint256).max - 1000) / 100);
        vm.startPrank(owner);

        vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, amount + 1000));
        address alice = address(2);
        vm.startPrank(alice);
        // mint tokens to alice
        depositToken.mint(alice, amount);

        // deposit tokens to vault
        depositToken.approve(address(vault), amount);
        vaultSupervisor.deposit(IVault(address(vault)), amount, amount);

        // start withdraw from vault for 50% of shares allocated to alice
        (IVault[] memory xaults, IERC20[] memory tokens, uint256[] memory assets, uint256[] memory shares) =
            vaultSupervisor.getDeposits(alice);
        (Withdraw.QueuedWithdrawal[] memory withdrawConfigs) = started_withdraw_fixture(shares[0] / 2, alice);

        assertEq(
            keccak256(abi.encode(delegationSupervisor.fetchQueuedWithdrawals(address(alice)))),
            keccak256(abi.encode(withdrawConfigs))
        );
        assertTrue(delegationSupervisor.isWithdrawPending(withdrawConfigs[0]));

        vm.warp(1000);
        delegationSupervisor.finishWithdraw(withdrawConfigs);
        assertFalse(delegationSupervisor.isWithdrawPending(withdrawConfigs[0]));
        assertEq(depositToken.balanceOf(address(alice)), amount / 2);
    }
}
