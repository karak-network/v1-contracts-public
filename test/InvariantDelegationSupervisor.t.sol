// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";

import "../src/Vault.sol";
import "../src/interfaces/IVaultSupervisor.sol";
import "../src/interfaces/IDelegationSupervisor.sol";
import "../src/VaultSupervisor.sol";
import "../src/DelegationSupervisor.sol";
import "./utils/ERC20Mintable.sol";
import "./utils/ProxyDeployment.sol";
import "../src/interfaces/Errors.sol";
import "./utils/InvariantHandlers.sol";

contract InvariantDelegationSupervisorTest is Test {
    IVault vault;
    IVaultSupervisor vaultSupervisor;
    DelegationSupervisor delegationSupervisor;
    address owner = address(7);
    address manager = address(8);
    ERC20Mintable depositToken;
    address operatorRewards = address(3);
    address proxyAdmin = address(11);
    DelegationSupervisorHandler handler;

    function setUp() public {
        address vaultImpl = address(new Vault());
        vaultSupervisor = IVaultSupervisor(ProxyDeployment.factoryDeploy(address(new VaultSupervisor()), proxyAdmin));
        delegationSupervisor =
            DelegationSupervisor(ProxyDeployment.factoryDeploy(address(new DelegationSupervisor()), proxyAdmin));

        vm.startPrank(owner);
        vaultSupervisor.initialize(address(delegationSupervisor), vaultImpl, ILimiter(address(0)), manager);

        depositToken = new ERC20Mintable();

        vault = vaultSupervisor.deployVault(IERC20(address(depositToken)), "Test", "TST", IVault.AssetType.ETH);
        vaultSupervisor.runAdminOperation(vault, abi.encodeCall(IVault.setLimit, type(uint256).max));

        vm.stopPrank();

        vm.startPrank(owner);
        delegationSupervisor.initialize(address(vaultSupervisor), 10, manager);
        handler = new DelegationSupervisorHandler(delegationSupervisor, vaultSupervisor, vault, depositToken, owner);
        vm.stopPrank();

        vm.startPrank(address(handler));
        depositToken.mint(address(handler), 2000);
        depositToken.approve(address(vault), 2000);
        vaultSupervisor.deposit(IVault(address(vault)), 1000, 1000);
        targetContract(address(handler));
    }

    function invariant_shares_equal_assets() public {
        (IVault[] memory xaults, IERC20[] memory tokens, uint256[] memory assets, uint256[] memory shares) =
            vaultSupervisor.getDeposits(address(handler));
        assertEq(assets, shares);
    }
}
