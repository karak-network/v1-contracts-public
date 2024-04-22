// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.21;

import {ERC4626} from "solady/src/tokens/ERC4626.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/Errors.sol";
import "./interfaces/IVault.sol";

contract Vault is ERC4626, Initializable, Ownable, PausableUpgradeable, ReentrancyGuard {
    IERC20 public depositToken;
    uint256 public assetLimit;
    IVault.AssetType public assetType;

    uint8 private _decimals;
    string private nameStr;
    string private symbolStr;

    uint256[44] private __gap;

    /* ========== MUTATIVE FUNCTIONS ========== */

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        IERC20 _depositToken,
        string memory _name,
        string memory _symbol,
        IVault.AssetType _assetType
    ) external initializer {
        if (_assetType == IVault.AssetType.NONE) revert TokenNotEnabled();

        _initializeOwner(_owner);
        __Pausable_init();
        depositToken = _depositToken;
        nameStr = _name;
        symbolStr = _symbol;
        (bool success, uint8 result) = _tryGetAssetDecimals(address(_depositToken));
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
        assetType = _assetType;
    }

    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice ERC4626 `_deposit` implementation calls `maxDeposit` which checks the asset limit
     */
    function deposit(uint256 assets, address depositor)
        public
        override
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        if (assets > maxDeposit(depositor)) revert DepositMoreThanMax();
        shares = previewDeposit(assets);
        // by: the user
        // to: the vaultSupervisor
        _deposit({by: depositor, to: msg.sender, assets: assets, shares: shares});
    }

    function mint(uint256 shares, address to)
        public
        override
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        return super.mint(shares, to);
    }

    function withdraw(uint256 assets, address to, address owner)
        public
        override
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        return super.withdraw(assets, to, owner);
    }

    function redeem(uint256 shares, address to, address owner)
        public
        override
        onlyOwner
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        return super.redeem(shares, to, owner);
    }

    function setLimit(uint256 newLimit) external onlySupervisor {
        assetLimit = newLimit;
    }

    function pause(bool toPause) external onlySupervisor {
        if (toPause) _pause();
        else _unpause();
    }

    /* ========== VIEWS ========== */

    function maxDeposit(address to) public view override returns (uint256 maxAssets) {
        to = to; // Silence unused variable warning.
        maxAssets = assetLimit <= totalAssets() ? 0 : assetLimit - totalAssets();
    }

    function name() public view override returns (string memory) {
        return nameStr;
    }

    function symbol() public view override returns (string memory) {
        return symbolStr;
    }

    function asset() public view override returns (address) {
        return address(depositToken);
    }

    /* ========== MODIFIERS ========== */

    modifier onlySupervisor() {
        _checkOwner();
        _;
    }
}
