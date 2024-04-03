pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "solady/src/tokens/ERC4626.sol";
import "solady/src/auth/Ownable.sol";

import "../src/Vault.sol";
import "../src/VaultSupervisor.sol";
import "./utils/ERC20Mintable.sol";
import "./utils/ProxyDeployment.sol";
import "../src/interfaces/Errors.sol";

contract VaultTest is Test {
    Vault vault;
    VaultSupervisor vaultSupervisor;
    ERC20Mintable depositToken;
    address proxyAdmin = address(11);
    address delegationSupervisor = address(12);
    address notOwner = address(13);
    ILimiter limiter = ILimiter(address(3));
    address manager = address(12);

    function setUp() public {
        vaultSupervisor = VaultSupervisor(ProxyDeployment.factoryDeploy(address(new VaultSupervisor()), proxyAdmin));
        address vaultImpl = address(new Vault());
        vaultSupervisor.initialize(delegationSupervisor, vaultImpl, limiter, manager);
        depositToken = new ERC20Mintable();
        depositToken.initialize("Test", "TST", 18);
        vm.prank(manager);
        vault = Vault(
            address(vaultSupervisor.deployVault(IERC20(address(depositToken)), "TestVault", "TV", IVault.AssetType.ETH))
        );
    }

    function setLimit(uint256 limit) public {
        vm.prank(address(vaultSupervisor));
        vault.setLimit(limit);
    }

    function deposit(uint256 amount) public {
        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vault.deposit(amount, address(this));
    }

    function test_initialize_fail_noneAssetType() public {
        vm.expectRevert(TokenNotEnabled.selector);
        vm.prank(manager);
        Vault(
            address(
                vaultSupervisor.deployVault(IERC20(address(depositToken)), "TestVault", "TV", IVault.AssetType.NONE)
            )
        );
    }

    function test_initialize_fail_reinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(address(vaultSupervisor), IERC20(address(depositToken)), "Test1", "TST1", IVault.AssetType.ETH);
    }

    function test_initialize() public view {
        assertEq(address(vault.owner()), address(vaultSupervisor));
        assertEq(address(vault.depositToken()), address(depositToken));
        assertEq(vault.owner(), address(vaultSupervisor));
        assertEq(vault.name(), "TestVault");
        assertEq(vault.symbol(), "TV");
        assertEq(vault.decimals(), 18);
    }

    function test_setLimit_notOwner(uint256 limit) public {
        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        vault.setLimit(limit);
    }

    function test_setLimit_owner(uint256 limit) public {
        vm.assume(limit >= 0);
        setLimit(limit);
        assertEq(vault.assetLimit(), limit);
    }

    function test_deposit_revert_zero() public {
        vm.prank(address(vaultSupervisor));
        vm.expectRevert(ZeroAmount.selector);
        vault.deposit(0, address(this));
    }

    function test_deposit_no_approval(uint256 amount) public {
        vm.assume(amount > 0);
        setLimit(amount);

        depositToken.mint(address(this), amount);

        vm.prank(address(vaultSupervisor));
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        vault.deposit(amount, address(this));
    }

    function test_deposit_no_tokens(uint256 amount) public {
        vm.assume(amount > 0);
        setLimit(amount);

        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        vault.deposit(amount, address(this));
    }

    function test_deposit_paused(uint256 amount) public {
        vm.assume(amount > 0);
        setLimit(amount);

        vm.prank(address(vaultSupervisor));
        vault.pause(true);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.deposit(amount, address(this));
    }

    function test_deposit_not_manager(uint256 amount) public {
        vm.assume(amount > 0);
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(notOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        vault.deposit(amount, address(this));
    }

    function test_deposit_beyond_limit(uint256 amount, uint256 limit) public {
        vm.assume(limit > 0);
        vm.assume(amount > limit);
        setLimit(limit);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vm.prank(address(vaultSupervisor));
        vm.expectRevert(ERC4626.DepositMoreThanMax.selector);
        vault.deposit(amount, address(this));
    }

    function test_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        setLimit(amount);

        deposit(amount);

        assertEq(depositToken.balanceOf(address(vault)), amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.totalSupply(), amount);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_multiple_deposits(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2);

        test_deposit(amount);
        setLimit(amount * 2);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vm.prank(address(vaultSupervisor));
        vault.deposit(amount, address(this));

        assertEq(depositToken.balanceOf(address(vault)), amount * 2);
        assertEq(vault.totalAssets(), amount * 2);
        assertEq(vault.totalSupply(), amount * 2);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount * 2);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_multiple_deposits_with_time(uint256 amount, uint256 secondsLater) public {
        vm.assume(secondsLater > 0 && secondsLater < 3650 days);
        vm.assume(amount < type(uint256).max / 2);

        test_deposit(amount);
        setLimit(amount * 2);

        StdCheats.skip(secondsLater);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vm.prank(address(vaultSupervisor));
        vault.deposit(amount, address(this));

        assertEq(depositToken.balanceOf(address(vault)), amount * 2);
        assertEq(vault.totalAssets(), amount * 2);
        assertEq(vault.totalSupply(), amount * 2);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount * 2);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_multiple_deposits_with_time_and_yield(uint256 amount, uint256 yield, uint256 secondsLater) public {
        vm.assume(secondsLater > 0 && secondsLater < 3650 days);
        vm.assume(amount < type(uint256).max / 2);
        vm.assume(yield < type(uint256).max - amount * 2);

        test_deposit(amount);
        setLimit(type(uint256).max - 1);

        // Add yield
        depositToken.mint(address(vault), yield);

        StdCheats.skip(secondsLater);
        uint256 expectedNewShares = vault.previewDeposit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vm.startPrank(address(vaultSupervisor));
        vault.deposit(amount, address(this));

        assertEq(depositToken.balanceOf(address(vault)), amount * 2 + yield);
        assertEq(vault.totalAssets(), amount * 2 + yield);
        assertEq(vault.totalSupply(), amount + expectedNewShares);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount + expectedNewShares);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_redeem_notOwner() public {
        uint256 amount = 1000;
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vault.deposit(amount, address(this));

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(notOwner);
        vault.withdraw(amount, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_redeem_paused() public {
        uint256 amount = 1000;
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.startPrank(address(vaultSupervisor));
        vault.deposit(amount, address(this));
        vault.pause(true);
        vm.stopPrank();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(address(vaultSupervisor));
        vault.withdraw(amount, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_redeem_no_shares(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2);
        setLimit(amount);

        vm.prank(address(vaultSupervisor));
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        vault.redeem(amount, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_redeem_zero_amount() public {
        vm.prank(address(vaultSupervisor));
        vm.expectRevert(ZeroAmount.selector);
        vault.redeem(0, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_fail_redeem(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max);

        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.startPrank(address(vaultSupervisor));
        uint256 shares = vault.deposit(amount, address(this));
        assertEq(depositToken.balanceOf(address(this)), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount);

        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        vault.redeem(shares + 1, address(this), address(this));
    }

    function test_redeem(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2);
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.startPrank(address(vaultSupervisor));
        uint256 shares = vault.deposit(amount, address(this));
        vm.stopPrank();

        assertEq(depositToken.balanceOf(address(this)), 0);
        assertEq(depositToken.balanceOf(address(vault)), amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.totalSupply(), amount);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount);
        assertEq(vault.balanceOf(address(this)), 0);

        vm.prank(address(vaultSupervisor));
        vault.redeem(shares, address(vaultSupervisor), address(vaultSupervisor));
        assertEq(depositToken.balanceOf(address(vaultSupervisor)), amount);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_withdraw_notOwner() public {
        uint256 amount = 1000;
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vault.deposit(amount, address(this));

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(notOwner);
        vault.withdraw(amount, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_withdraw_paused() public {
        uint256 amount = 1000;
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.startPrank(address(vaultSupervisor));
        vault.deposit(amount, address(this));
        vault.pause(true);
        vm.stopPrank();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(address(vaultSupervisor));
        vault.withdraw(amount, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_withdraw_zero() public {
        vm.expectRevert(ZeroAmount.selector);
        vm.startPrank(address(vaultSupervisor));
        vault.withdraw(0, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_fail_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vault.deposit(amount, address(this));

        assertEq(depositToken.balanceOf(address(this)), 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount);

        vm.prank(address(vaultSupervisor));
        vm.expectRevert();
        vault.withdraw(amount + 1, address(vaultSupervisor), address(vaultSupervisor));
    }

    function test_withdraw(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max);
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        uint256 shares = vault.deposit(amount, address(this));

        assertEq(depositToken.balanceOf(address(vault)), amount);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.totalSupply(), amount);
        assertEq(vault.balanceOf(address(vaultSupervisor)), amount);
        assertEq(vault.balanceOf(address(this)), 0);

        vm.prank(address(vaultSupervisor));
        vault.withdraw(shares, address(vaultSupervisor), address(vaultSupervisor));
        assertEq(depositToken.balanceOf(address(vaultSupervisor)), amount);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_asset_address(uint256 amount) public {
        vm.assume(amount > 0);
        test_deposit(amount);
        assertEq(address(depositToken), vault.asset());
    }

    function test_maxDeposit(uint256 limit, uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(limit > amount);

        setLimit(limit);
        deposit(amount);
        assertEq(vault.maxDeposit(address(vault)), limit - amount);
    }

    function test_unpause(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < (type(uint256).max / 2) - 1);
        setLimit(amount * 2);

        vm.prank(address(vaultSupervisor));
        vault.pause(true);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        vm.prank(address(vaultSupervisor));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.deposit(amount, address(this));

        vm.prank(address(vaultSupervisor));
        vault.pause(false);
        deposit(amount);
    }
}
