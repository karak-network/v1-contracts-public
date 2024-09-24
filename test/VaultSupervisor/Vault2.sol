// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import "../../src/interfaces/IVault2.sol";
import "../../src/Vault.sol";

contract Vault2 is Vault {
    function deposit(uint256 assets, address beneficiary, uint256 minSharesOut) external returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        shares = ERC4626.deposit(assets, beneficiary);
        if (shares < minSharesOut) revert NotEnoughShares();
    }
}
