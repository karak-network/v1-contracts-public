pragma solidity ^0.8.17;

import "solady/src/tokens/ERC20.sol";

contract ERC20Mintable is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    function initialize(string memory name_, string memory symbol_, uint8 decimals_) external {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external virtual {
        if (to == address(0)) revert AddressZero();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external virtual {
        if (from == address(0)) revert AddressZero();
        _burn(from, amount);
    }

    /// @dev Returns the name of the token.
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns the decimals places of the token.
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    error AddressZero();
}
