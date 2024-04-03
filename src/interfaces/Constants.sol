// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";

library Constants {
    uint256 public constant MAX_WITHDRAWAL_DELAY = 30 days;

    uint8 public constant MAX_VAULTS_PER_STAKER = 32;

    bytes32 public constant SIGNED_DEPOSIT_TYPEHASH =
        keccak256("Deposit(address vault, uint256 deadline, uint256 value, uint256 nonce)");

    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    address public constant DEFAULT_VAULT_IMPLEMENTATION_FLAG = address(1);

    // Bit from solady/src/auth/OwnableRoles.sol
    uint256 public constant MANAGER_ROLE = 1 << 0;
}
