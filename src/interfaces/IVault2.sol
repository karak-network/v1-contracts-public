// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {WithdrawLib2} from "../entities/Withdraw2.sol";
import {VaultLib2} from "../entities/VaultLib2.sol";

interface IVault2 {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function initialize(
        address _owner,
        address _operator,
        address _depositToken,
        string memory _name,
        string memory _symbol,
        bytes memory _extraData
    ) external;
    function deposit(uint256 assets, address to) external returns (uint256 shares);
    function deposit(uint256 assets, address to, uint256 minSharesOut) external returns (uint256 shares);
    function mint(uint256 shares, address to) external returns (uint256 assets);
    function startRedeem(uint256 shares, address withdrawer) external returns (bytes32 withdrawalKey);
    function finishRedeem(bytes32 withdrawalKey) external;
    function pause(uint256 map) external;
    function unpause(uint256 map) external;
    function slashAssets(uint256 slashPercentageWad, address slashingHandler)
        external
        returns (uint256 transferAmount);
    /* ======================================== */

    /* ============ VIEW FUNCTIONS ============ */
    function owner() external view returns (address);
    function totalAssets() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function vaultConfig() external pure returns (VaultLib2.Config memory);
    function asset() external view returns (address);
    function getNextWithdrawNonce(address staker) external view returns (uint256);
    function isWithdrawalPending(address staker, uint256 _withdrawNonce) external view returns (bool);
    function getQueuedWithdrawal(address staker, uint256 _withdrawNonce)
        external
        view
        returns (WithdrawLib2.QueuedWithdrawal memory);
    /* ======================================== */
}
