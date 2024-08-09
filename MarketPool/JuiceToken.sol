// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract JuiceToken is ERC20 {
    constructor(address _to) ERC20("Juice", "JUICE") {
        _mint(_to, 1_000_000_000 * 10 ** 18);
    }
}
