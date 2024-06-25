## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

### Changelog

## Version 1.2

- Fixes `gimmieShares` reentrancy guard issue where `depositAndGimmie` wasn't functional due to two reentrancy guards in the same flow.
- Added Pendle rollover support allowing for maturing PT assets to:

  1. In 1 admin tx, redeem all the old PT assets from a given vault for the underlying asset via Pendle. Update the vault's asset to the underlyingAsset. Users with pending withdraws can complete them still and get the underlying asset instead of the PT asset.
  2. Each user can convert the underlyingAsset from a vault to the new PT asset and have that PT asset deposited into the appropriate vault.

  PRs:

  - https://github.com/karak-network/karak-restaking/pull/273 (has useful diagrams)
  - https://github.com/karak-network/karak-restaking/pull/277

## Version 1.1

- Adds `gimmieShares`, `depositAndGimmie` and `returnShares` functionality to the contract to allow for depositor to get their receipt tokens out from the supervisor.
