// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

library VaultLib2 {
    struct Config {
        // Required fields
        address asset;
        uint8 decimals;
        address operator;
        string name;
        string symbol;
        bytes extraData;
    }
}
