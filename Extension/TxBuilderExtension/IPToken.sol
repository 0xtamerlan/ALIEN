// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../data/IERC20.sol";

interface IPToken is IERC20 {
    function getUnderlying() external view returns (address);

    function wrap(uint256 amount) external;

    function unwrap(uint256 amount) external;

    function absorb(address user) external;
}
