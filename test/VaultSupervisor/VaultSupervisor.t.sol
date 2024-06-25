pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import "solady/src/utils/SafeTransferLib.sol";
import "solady/src/tokens/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "../../src/Vault.sol";
import "../../src/Limiter.sol";
import "../../src/interfaces/ILimiter.sol";
import "../../src/interfaces/IVaultSupervisor.sol";
import "../harnesses/VaultSupervisorHarness.sol";
import {ERC20PermitMintable} from "../utils/ERC20PermitMintable.sol";
import "../utils/ProxyDeployment.sol";
import "../utils/SigUtils.sol";

contract VaultSupervisorTest is Test {
    IVault vault;
    VaultSupervisorHarness vaultSupervisor;
    ERC20PermitMintable depositToken;
    ILimiter limiter;
    SigUtils sigUtils;

    event UpgradedAllVaults(address indexed implementation);
    event UpgradedVault(address indexed implementation, address indexed vault);

    address delegationSupervisor = address(1);
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    address proxyAdmin = address(11);
    address vaultImpl;
    address manager = address(12);

    function setUp() public {
        vaultImpl = address(new Vault());
        vaultSupervisor =
            VaultSupervisorHarness(ProxyDeployment.factoryDeploy(address(new VaultSupervisorHarness()), proxyAdmin));
        limiter = ILimiter(new Limiter(1, 1, type(uint256).max));
        vaultSupervisor.initialize(delegationSupervisor, vaultImpl, limiter, manager);
        depositToken = new ERC20PermitMintable();
        depositToken.initialize("Test", "TST", 18);

        vm.prank(manager);
        vault = vaultSupervisor.deployVault(IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH);

        setLimit(1000);

        sigUtils = new SigUtils(IERC20Permit(address(vault.asset())).DOMAIN_SEPARATOR());
    }

    function setLimit(uint256 limit) public {
        vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, limit));
    }

    function deposit(uint256 amount) public returns (uint256 shares) {
        setLimit(amount);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);

        shares = vaultSupervisor.deposit(vault, amount, amount);
    }

    function test_init_delegationSupervisor_zeroAddr() public {
        vaultSupervisor =
            VaultSupervisorHarness(ProxyDeployment.factoryDeploy(address(new VaultSupervisorHarness()), proxyAdmin));
        vm.expectRevert(ZeroAddress.selector);
        vaultSupervisor.initialize(address(0), address(1), limiter, manager);
    }

    function test_init_vaultImp_zeroAddr() public {
        vaultSupervisor =
            VaultSupervisorHarness(ProxyDeployment.factoryDeploy(address(new VaultSupervisorHarness()), proxyAdmin));
        vm.expectRevert(ZeroAddress.selector);
        vaultSupervisor.initialize(address(1), address(0), limiter, manager);
    }

    function test_initialize_reinit() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(address(vaultSupervisor), IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH);
    }

    function test_initialize() public view {
        assertEq(address(vault.owner()), address(vaultSupervisor));
        assertEq(address(vaultSupervisor.delegationSupervisor()), delegationSupervisor);
        assertEq(address(vaultSupervisor.implementation()), vaultImpl);
    }

    function test_deposit_zeroAmount() public {
        vm.expectRevert(ZeroAmount.selector);
        vaultSupervisor.deposit(vault, 0, 1);
    }

    function test_deposit_noApproval(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);
        setLimit(amount);
        depositToken.mint(address(this), amount);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        vaultSupervisor.deposit(vault, amount, amount);
    }

    function test_deposit_no_tokens(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);
        setLimit(amount);
        depositToken.approve(address(this), amount);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        vaultSupervisor.deposit(vault, amount, amount);
    }

    function test_deposit_noEnoughShares(uint256 amount, uint256 minSharesOut) public {
        vm.assume(amount > 0);
        vm.assume(minSharesOut < type(uint256).max / 10);
        vm.assume(amount < minSharesOut);
        setLimit(amount);
        depositToken.approve(address(this), amount);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        vaultSupervisor.deposit(vault, amount, minSharesOut);
    }

    function test_deposit_paused() public {
        vm.prank(manager);
        vaultSupervisor.pause(true);

        vm.prank(address(100001));
        vm.expectRevert(Ownable.Unauthorized.selector);
        vaultSupervisor.pause(true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vaultSupervisor.deposit(vault, 1000, 1000);
    }

    function test_deposit_vaultDoesntExist(address vaultAddr) public {
        vm.assume(vaultAddr != address(vault));
        vm.expectRevert(VaultNotAChildVault.selector);
        vaultSupervisor.deposit(IVault(vaultAddr), 1000, 1000);
    }

    function test_deposit_beyondLocalLimit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max - 1);
        setLimit(amount - 1);

        limiter.setGlobalUsdLimit(type(uint256).max);
        limiter.setUsdPerEth(1);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vm.expectRevert(ERC4626.DepositMoreThanMax.selector);
        vaultSupervisor.deposit(vault, amount, amount);
    }

    function test_deposit_beyondGlobalLimit(uint256 amount) public {
        setLimit(type(uint256).max);
        uint256 limit = 1e18;
        uint256 price = 1000;
        vm.assume(amount > limit / price);
        vm.assume(amount < type(uint256).max / price);

        limiter.setGlobalUsdLimit(limit);
        limiter.setUsdPerEth(price);

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vm.expectRevert(CrossedDepositLimit.selector);
        vaultSupervisor.deposit(vault, amount, amount);
    }

    function test_deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);
        vm.assume(amount < type(uint256).max);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);

        (IVault[] memory vaults, IERC20[] memory tokens, uint256[] memory assets,) =
            vaultSupervisor.getDeposits(address(this));
        assertEq(vaults.length, 1);
        assertEq(tokens.length, 1);
        assertEq(assets.length, 1);
        assertEq(address(vaults[0]), address(vault));
        assertEq(address(tokens[0]), address(depositToken));
        assertEq(assets[0], shares);
        assertEq(depositToken.balanceOf(address(this)), 0);
        assertEq(depositToken.balanceOf(address(vault)), amount);
    }

    function test_depositAndGimmie(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);
        vm.assume(amount < type(uint256).max);

        setLimit(amount);
        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        uint256 shares = vaultSupervisor.depositAndGimmie(vault, amount, amount);

        (IVault[] memory vaults, IERC20[] memory tokens, uint256[] memory assets,) =
            vaultSupervisor.getDeposits(address(this));
        assertEq(vaults.length, 0);
        assertEq(tokens.length, 0);
        assertEq(assets.length, 0);
        assertEq(depositToken.balanceOf(address(this)), 0);
        assertEq(depositToken.balanceOf(address(vault)), amount);
        assertEq(vault.balanceOf(address(this)), shares);
    }

    function test_deposit_globalLimiterSetToZero(uint256 amount) public {
        setLimit(type(uint256).max);

        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max);

        vm.prank(manager);
        vaultSupervisor.setLimiter(ILimiter(address(0)));

        depositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        vaultSupervisor.deposit(vault, amount, amount);
    }

    function test_deposit_multiple(uint256 amount) public {
        vm.assume(amount > 1);
        vm.assume(amount < type(uint256).max / 10);
        setLimit(amount * 2);

        depositToken.mint(address(this), amount * 2);
        depositToken.approve(address(vault), amount * 2);

        uint256 sharesFirst = vaultSupervisor.deposit(vault, amount, amount);
        assertEq(sharesFirst, amount);

        (IVault[] memory vaults, IERC20[] memory tokens, uint256[] memory assets, uint256[] memory shares) =
            vaultSupervisor.getDeposits(address(this));
        assertEq(vaults.length, 1);
        assertEq(tokens.length, 1);
        assertEq(assets.length, 1);
        assertEq(address(vaults[0]), address(vault));
        assertEq(address(tokens[0]), address(depositToken));
        assertEq(assets[0], sharesFirst);

        uint256 sharesSecond = vaultSupervisor.deposit(vault, amount, amount);
        assertEq(sharesSecond, amount);

        (vaults, tokens, assets, shares) = vaultSupervisor.getDeposits(address(this));
        assertEq(vaults.length, 1);
        assertEq(tokens.length, 1);
        assertEq(assets.length, 1);
        assertEq(address(vaults[0]), address(vault));
        assertEq(address(tokens[0]), address(depositToken));
        assertEq(assets[0], sharesFirst + sharesSecond);
        assertEq(depositToken.balanceOf(address(this)), 0);
        assertEq(depositToken.balanceOf(address(vault)), amount * 2);
    }

    function test_deposit_multiple_diffVaults(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);
        setLimit(amount);

        ERC20PermitMintable secondDepositToken = new ERC20PermitMintable();
        secondDepositToken.initialize("Test1", "TST1", 18);

        vm.prank(manager);
        IVault secondVault =
            vaultSupervisor.deployVault(IERC20(address(secondDepositToken)), "Test1", "TST1", IVault.AssetType.ETH);
        vaultSupervisor.runAdminOperation(secondVault, abi.encodeCall(IVault.setLimit, amount));

        depositToken.mint(address(this), amount);
        secondDepositToken.mint(address(this), amount);
        depositToken.approve(address(vault), amount);
        secondDepositToken.approve(address(secondVault), amount);

        uint256 sharesFirst = vaultSupervisor.deposit(vault, amount, amount);
        assertEq(sharesFirst, amount);

        uint256 sharesSecond = vaultSupervisor.deposit(secondVault, amount, amount);
        assertEq(sharesSecond, amount);

        (IVault[] memory vaults, IERC20[] memory tokens, uint256[] memory assets,) =
            vaultSupervisor.getDeposits(address(this));
        assertEq(vaults.length, 2);
        assertEq(tokens.length, 2);
        assertEq(assets.length, 2);
        assertEq(address(vaults[0]), address(vault));
        assertEq(address(vaults[1]), address(secondVault));
        assertEq(address(tokens[0]), address(depositToken));
        assertEq(address(tokens[1]), address(secondDepositToken));
        assertEq(assets[0], sharesFirst);
        assertEq(assets[1], sharesSecond);
    }

    function test_depositWithSignature(uint256 amount) public {
        setLimit(amount);
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        depositToken.mint(alice, amount);
        vm.prank(alice);
        depositToken.approve(address(vault), amount);

        (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign) =
            getSignatures(alice, alicePk, amount);
        uint256 shares =
            vaultSupervisor.depositWithSignature(vault, alice, amount, amount, block.number + 10, permitSign, vaultSign);
        assertEq(shares, amount);
    }

    function test_depositWithSignature_InvalidVaultHashNonce(uint256 amount) public {
        setLimit(amount);
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        depositToken.mint(alice, amount);
        vm.prank(alice);

        (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign) =
            getSignaturesVaultHashInvalidNonce(alice, alicePk, amount);

        vm.expectRevert(InvalidSignature.selector);
        vaultSupervisor.depositWithSignature(vault, alice, amount, amount, block.number + 10, permitSign, vaultSign);
    }

    function test_depositWithSignature_InvalidVaultHashValue(uint256 amount, uint256 wrongAmountForSign) public {
        setLimit(amount);
        vm.assume(amount > 0);
        vm.assume(wrongAmountForSign > 0);
        vm.assume(amount != wrongAmountForSign);
        vm.assume(amount < type(uint256).max / 10);
        vm.assume(wrongAmountForSign < type(uint256).max);

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        depositToken.mint(alice, amount);
        vm.prank(alice);

        (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign) =
            getSignaturesVaultHashInvalidValue(alice, alicePk, amount, wrongAmountForSign);
        vm.expectRevert(InvalidSignature.selector);
        vaultSupervisor.depositWithSignature(vault, alice, amount, amount, block.number + 10, permitSign, vaultSign);
    }

    function test_depositWithSignature_SignatureDeadlinePassed(uint256 amount) public {
        setLimit(amount);
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max);

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        depositToken.mint(alice, amount);
        vm.prank(alice);
        (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign) =
            getSignatures(alice, alicePk, amount);

        vm.roll(block.timestamp + 11);
        vm.expectRevert(PermitFailed.selector);
        vaultSupervisor.depositWithSignature(vault, alice, amount, amount, block.number + 10, permitSign, vaultSign);
    }

    function test_depositWithSignature_BadPermitButAllowance(uint256 amount) public {
        setLimit(amount);
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        (address alice, uint256 alicePk) = makeAddrAndKey("alice");

        depositToken.mint(alice, amount);
        vm.prank(alice);
        (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign) =
            getSignaturesInvalidPermitSign(alice, alicePk, amount);

        vm.prank(alice);
        depositToken.approve(address(vault), amount);
        vaultSupervisor.depositWithSignature(vault, alice, amount, amount, block.number + 10, permitSign, vaultSign);
    }

    function test_gimmieShares(uint256 amountToDeposit, uint256 amountToGimmie) public {
        vm.assume(amountToGimmie > 0);
        vm.assume(amountToDeposit >= amountToGimmie);
        vm.assume(amountToDeposit > 0);
        vm.assume(amountToDeposit < type(uint256).max / 10);

        uint256 shares = deposit(amountToDeposit);
        assertEq(shares, amountToDeposit);

        vaultSupervisor.gimmieShares(vault, amountToGimmie);

        // underlying asset shouldn't leave the vault
        assertEq(depositToken.balanceOf(address(vault)), amountToDeposit);

        // user should get the amount they asked for
        assertEq(vault.balanceOf(address(this)), amountToGimmie);

        // remaining funds should stay in the vault supervisor
        assertEq(vault.balanceOf(address(vaultSupervisor)), amountToDeposit - amountToGimmie);

        // tracked shares of the user should change
        assertEq(vaultSupervisor.getShares(address(this), vault), amountToDeposit - amountToGimmie);
    }

    function test_returnShares(uint256 amountToDeposit, uint256 amountToGimmie, uint256 amountToReturn) public {
        vm.assume(amountToReturn > 0);
        vm.assume(amountToGimmie >= amountToReturn);
        test_gimmieShares(amountToDeposit, amountToGimmie);

        vault.approve(address(vaultSupervisor), amountToReturn);
        vaultSupervisor.returnShares(vault, amountToReturn);

        // underlying asset shouldn't be changed after return eithehr
        assertEq(depositToken.balanceOf(address(vault)), amountToDeposit);

        // tracked shares of the user should change
        assertEq(vaultSupervisor.getShares(address(this), vault), amountToDeposit - amountToGimmie + amountToReturn);
    }

    function test_changeImplementation_notOwner() public {
        address randomAddress = address(13);
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(randomAddress);
        vaultSupervisor.changeImplementation(address(2));
    }

    function test_changeImplementation_zeroAddr() public {
        vm.expectRevert(ZeroAddress.selector);
        vaultSupervisor.changeImplementation(address(0));
    }

    function test_changeImplementation() public {
        vaultSupervisor.changeImplementation(address(2));
        assertEq(address(vaultSupervisor.implementation()), address(2));
    }

    function test_changeImplementationForVault_notOwner() public {
        address randomAddress = address(13);
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(randomAddress);
        vaultSupervisor.changeImplementationForVault(address(vault), address(2));
    }

    function test_changeImplementationForVault_zeroAddr() public {
        vm.expectRevert(ZeroAddress.selector);
        vaultSupervisor.changeImplementationForVault(address(vault), address(0));
    }

    function test_changeImplementationForVault_notAVault() public {
        vm.expectRevert(VaultNotAChildVault.selector);
        vaultSupervisor.changeImplementationForVault(address(100001), address(2));
    }

    function test_changeImplementationForVault() public {
        vaultSupervisor.changeImplementationForVault(address(vault), address(2));
        assertEq(address(vaultSupervisor.implementation(address(vault))), address(2));
    }

    function test_deployVault_notManagerOrOwner() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(address(10001));
        vaultSupervisor.deployVault(depositToken, "Test", "TST", IVault.AssetType.ETH);
    }

    function test_setLimiter_notManagerOrOwner() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(address(10001));
        vaultSupervisor.setLimiter(ILimiter(address(999)));
    }

    function test_setLimiter_nonZero() public {
        vm.prank(manager);
        vaultSupervisor.setLimiter(ILimiter(address(999)));
        assertEq(address(vaultSupervisor.limiter()), address(999));
    }

    function test_setLimiter_zero() public {
        vm.prank(manager);
        vaultSupervisor.setLimiter(ILimiter(address(0)));
        assertEq(address(vaultSupervisor.limiter()), address(0));
    }

    function test_redeemShares(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);

        vm.startPrank(address(delegationSupervisor));
        vaultSupervisor.redeemShares(address(this), vault, shares);
        vm.stopPrank();

        assertEq(depositToken.balanceOf(address(this)), amount);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function test_redeemShares_notDelegationSupervisor(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);
        vm.expectRevert(NotDelegationSupervisor.selector);
        vaultSupervisor.redeemShares(address(vaultSupervisor), vault, shares);
    }

    function test_redeemShares_notChildVault(uint256 amount, address vaultAddr) public {
        vm.assume(vaultAddr != address(vault));
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);

        vm.prank(address(delegationSupervisor));
        vm.expectRevert(VaultNotAChildVault.selector);
        vaultSupervisor.redeemShares(address(this), IVault(vaultAddr), shares);
    }

    function test_removeShares(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);

        vm.prank(address(delegationSupervisor));
        vaultSupervisor.removeShares(address(this), vault, shares);

        (,,, uint256[] memory depositShares) = vaultSupervisor.getDeposits(address(this));
        assertEq(depositShares.length, 0);
    }

    function test_removeShares_notChildVault(uint256 amount, address vaultAddr) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);

        vm.prank(address(delegationSupervisor));
        vm.expectRevert(VaultNotAChildVault.selector);
        vaultSupervisor.removeShares(address(this), IVault(vaultAddr), shares);
    }

    function test_removeShares_notDelegationSupervisor(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 10);

        uint256 shares = deposit(amount);
        assertEq(shares, amount);
        vm.expectRevert(NotDelegationSupervisor.selector);
        vaultSupervisor.removeShares(address(vaultSupervisor), vault, shares);
    }

    function test_removeShares_NotEnough(uint256 shares) public {
        vm.assume(shares > 0);

        vm.prank(address(delegationSupervisor));
        vm.expectRevert(NotEnoughShares.selector);
        vaultSupervisor.removeShares(address(this), vault, shares);
    }

    function getSignaturesVaultHashInvalidValue(
        address alice,
        uint256 alicePk,
        uint256 amount,
        uint256 wrongAmountForSign
    )
        internal
        view
        returns (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign)
    {
        permitSign = getErc20PermitSign(
            alice,
            alicePk,
            address(vault),
            amount,
            uint256(IERC20Permit(address(vault.asset())).nonces(alice)),
            uint256(block.number + 10)
        );
        bytes32 EIP712DomainHash = keccak256(
            abi.encode(
                Constants.DOMAIN_TYPEHASH,
                keccak256(bytes("Karak_Vault_Sup")),
                keccak256(bytes("v1")),
                block.chainid,
                address(vaultSupervisor)
            )
        );
        bytes32 vaultHash = keccak256(
            abi.encodePacked(
                vaultSupervisor.SIGNED_DEPOSIT_TYPEHASH(),
                address(vault),
                uint256(block.timestamp + 10),
                wrongAmountForSign,
                vaultSupervisor.getUserNonce(alice)
            )
        );
        bytes32 combinedHash = keccak256(abi.encodePacked("\x19\x01", EIP712DomainHash, vaultHash));
        (uint8 vaultV, bytes32 vaultR, bytes32 vaultS) = vm.sign(alicePk, combinedHash);
        vaultSign = IVaultSupervisor.Signature({v: vaultV, r: vaultR, s: vaultS});
    }

    function test_changeImplementation(address newImpl) public {
        address currentImpl = vaultSupervisor.implementation();
        vm.assume(newImpl != address(0));
        vm.assume(newImpl != currentImpl);

        vaultSupervisor.changeImplementation(newImpl);
        assertEq(address(vaultSupervisor.implementation()), newImpl);
        assertNotEq(address(vaultSupervisor.implementation()), currentImpl);
    }

    function test_changeImplementation_zeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        vaultSupervisor.changeImplementation(address(0));
    }

    function changeImplementationForVault(address newVault) public {
        vm.expectEmit(true, true, false, true);
        emit UpgradedVault(newVault, address(vault));
        vaultSupervisor.changeImplementationForVault(address(vault), newVault);
    }

    function test_changeImplementationForVault_zeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        vaultSupervisor.changeImplementationForVault(address(vault), address(0));
    }

    function getSignatures(address alice, uint256 alicePk, uint256 amount)
        internal
        view
        returns (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign)
    {
        permitSign = getErc20PermitSign(
            alice,
            alicePk,
            address(vault),
            uint256(amount),
            uint256(IERC20Permit(address(vault.asset())).nonces(alice)),
            uint256(block.number + 10)
        );
        bytes32 EIP712DomainHash = keccak256(
            abi.encode(
                Constants.DOMAIN_TYPEHASH,
                keccak256(bytes("Karak_Vault_Sup")),
                keccak256(bytes("v1")),
                block.chainid,
                address(vaultSupervisor)
            )
        );
        bytes32 vaultHash = keccak256(
            abi.encodePacked(
                vaultSupervisor.SIGNED_DEPOSIT_TYPEHASH(),
                address(vault),
                uint256(block.timestamp + 10),
                uint256(amount),
                uint256(amount),
                vaultSupervisor.getUserNonce(alice)
            )
        );
        bytes32 combinedHash = keccak256(abi.encodePacked("\x19\x01", EIP712DomainHash, vaultHash));
        (uint8 vaultV, bytes32 vaultR, bytes32 vaultS) = vm.sign(alicePk, combinedHash);
        vaultSign = IVaultSupervisor.Signature({v: vaultV, r: vaultR, s: vaultS});
    }

    function getErc20PermitSign(
        address owner,
        uint256 ownerPk,
        address vaultAddress,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (IVaultSupervisor.Signature memory permitSign) {
        bytes32 permitHash = sigUtils.getTypedDataHash(
            Permit({owner: owner, spender: vaultAddress, value: value, nonce: nonce, deadline: deadline})
        );
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(ownerPk, permitHash);
        permitSign = IVaultSupervisor.Signature({v: permitV, r: permitR, s: permitS});
    }

    function getSignaturesVaultHashInvalidNonce(address alice, uint256 alicePk, uint256 amount)
        internal
        view
        returns (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign)
    {
        permitSign = getErc20PermitSign(
            alice,
            alicePk,
            address(vault),
            uint256(amount),
            uint256(IERC20Permit(address(vault.asset())).nonces(alice)),
            uint256(block.number + 10)
        );
        bytes32 EIP712DomainHash = keccak256(
            abi.encode(
                Constants.DOMAIN_TYPEHASH,
                keccak256(bytes("Karak_Vault_Sup")),
                keccak256(bytes("v1")),
                block.chainid,
                address(vaultSupervisor)
            )
        );
        bytes32 vaultHash = keccak256(
            abi.encodePacked(
                vaultSupervisor.SIGNED_DEPOSIT_TYPEHASH(),
                address(vault),
                uint256(block.timestamp + 10),
                uint256(amount),
                uint256(amount),
                vaultSupervisor.getUserNonce(alice) + 1
            )
        );
        bytes32 combinedHash = keccak256(abi.encodePacked("\x19\x01", EIP712DomainHash, vaultHash));
        (uint8 vaultV, bytes32 vaultR, bytes32 vaultS) = vm.sign(alicePk, combinedHash);
        vaultSign = IVaultSupervisor.Signature({v: vaultV, r: vaultR, s: vaultS});
    }

    function getSignaturesInvalidPermitSign(address alice, uint256 alicePk, uint256 amount)
        internal
        view
        returns (IVaultSupervisor.Signature memory permitSign, IVaultSupervisor.Signature memory vaultSign)
    {
        permitSign = getErc20PermitSign(
            alice,
            alicePk,
            address(vault),
            // adding 1 so that permit always has wrong value
            uint256(amount + 1),
            uint256(IERC20Permit(address(vault.asset())).nonces(alice)),
            uint256(block.number + 10)
        );
        bytes32 EIP712DomainHash = keccak256(
            abi.encode(
                Constants.DOMAIN_TYPEHASH,
                keccak256(bytes("Karak_Vault_Sup")),
                keccak256(bytes("v1")),
                block.chainid,
                address(vaultSupervisor)
            )
        );
        bytes32 vaultHash = keccak256(
            abi.encodePacked(
                vaultSupervisor.SIGNED_DEPOSIT_TYPEHASH(),
                address(vault),
                uint256(block.timestamp + 10),
                uint256(amount),
                uint256(amount),
                vaultSupervisor.getUserNonce(alice)
            )
        );
        bytes32 combinedHash = keccak256(abi.encodePacked("\x19\x01", EIP712DomainHash, vaultHash));
        (uint8 vaultV, bytes32 vaultR, bytes32 vaultS) = vm.sign(alicePk, combinedHash);
        vaultSign = IVaultSupervisor.Signature({v: vaultV, r: vaultR, s: vaultS});
    }

    function test_Add_manager() public {
        address newManager = address(19);

        OwnableRoles(address(vaultSupervisor)).grantRoles(newManager, Constants.MANAGER_ROLE);
        assertTrue(OwnableRoles(address(vaultSupervisor)).hasAllRoles(newManager, Constants.MANAGER_ROLE));
        assertFalse(OwnableRoles(address(vaultSupervisor)).hasAllRoles(address(18), Constants.MANAGER_ROLE));
    }
}
