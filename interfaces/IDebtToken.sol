// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../data/IERC20.sol";
import "../data/IERC20Metadata.sol";

interface IDebtToken is IERC20, IERC20Metadata {
    function asset() external view returns (address);
}
