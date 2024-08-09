// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract DebtTokenStorage {
    /// @dev The name of the token
    string internal _name;

    /// @dev The symbol of the token
    string internal _symbol;

    /// @notice The Alien contract address
    address public alien;

    /// @notice The underlying token address
    address public market;
}
