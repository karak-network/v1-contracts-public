// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

error InvalidInput();
error InvalidWithdrawalDelay();
error ZeroAddress();
error NotVaultSupervisor();
error NotStaker();
error WithdrawAlreadyCompleted();
error MinWithdrawDelayNotPassed();
error WithdrawerNotCaller();
error ZeroShares();
error MaxStakerVault();
error VaultNotAChildVault();
error NotDelegationSupervisor();
error NotPreviousNorCurrentDelegationSupervisor();
error VaultNotFound();
error NotEnoughShares();
error InvalidVaultAdminFunction();
error NotInitialized();
error RoleNotGranted();

// Vault.sol
error NotSupervisor();
error TokenNotEnabled();

// Generic
error NoElementsInArray();
error ArrayLengthsNotEqual();
error ZeroAmount();

// VaultSupervisor.sol
error PermitFailed();
error ExpiredSign();
error InvalidSignature();
error CrossedDepositLimit();

// Limiter.sol
error UnsupportedAsset();
