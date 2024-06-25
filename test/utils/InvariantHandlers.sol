pragma solidity ^0.8.17;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import "forge-std/console.sol";

import "../../src/Vault.sol";
import "../../src/interfaces/IVaultSupervisor.sol";
import "../../src/interfaces/IDelegationSupervisor.sol";
import "../../src/VaultSupervisor.sol";
import "../../src/DelegationSupervisor.sol";
import "./ERC20Mintable.sol";

contract DelegationSupervisorHandler is CommonBase, StdCheats {
    DelegationSupervisor private delegationSupervisor;
    IVaultSupervisor private vaultSupervisor;
    IVault private vault;
    ERC20Mintable private depositToken;
    address private owner;

    constructor(
        DelegationSupervisor _delegationSupervisor,
        IVaultSupervisor _vaultSupervisor,
        IVault _vault,
        ERC20Mintable _depositToken,
        address _owner
    ) {
        delegationSupervisor = _delegationSupervisor;
        vaultSupervisor = _vaultSupervisor;
        vault = _vault;
        depositToken = _depositToken;
        owner = _owner;
    }

    function deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount < depositToken.balanceOf(address(this)));

        depositToken.approve(address(vault), amount);
        vaultSupervisor.deposit(vault, amount, amount);
    }

    function withdraw(uint256 amount) public {
        (IVault[] memory xaults, IERC20[] memory tokens, uint256[] memory assets, uint256[] memory shares) =
            vaultSupervisor.getDeposits(address(this));

        if (assets.length > 0) {
            vm.assume(amount < assets[0]);

            IVault[] memory vaults = new IVault[](1);
            vaults[0] = IVault(address(vault));
            Withdraw.WithdrawRequest[] memory queuedConfig = new Withdraw.WithdrawRequest[](1);
            queuedConfig[0] = Withdraw.WithdrawRequest({vaults: vaults, shares: shares, withdrawer: address(this)});
            (bytes32[] memory withdrawalRoots, Withdraw.QueuedWithdrawal[] memory withdrawConfigs) =
                delegationSupervisor.startWithdraw(queuedConfig);

            uint256 waitTime = delegationSupervisor.withdrawalDelay();
            vm.warp(block.timestamp + waitTime);

            delegationSupervisor.finishWithdraw(withdrawConfigs);
        }
    }
}
