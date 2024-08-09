/**
 * Submitted for verification at blastscan.io on 2024-03-04
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol
// lib/openzeppelin-contracts/contracts/utils/Context.sol
// src/interfaces/IBlast.sol
// lib/openzeppelin-contracts/contracts/access/Ownable.sol
// lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol
// lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol

// src/tokenomics/Alien.sol

import {ERC20} from "../../data/ERC20.sol";
import {Ownable} from "../../data/Ownable.sol";
import {IBlast} from "../../interfaces/IBlast.sol";

contract Alien is ERC20, Ownable {
    //gas mode setting address
    address internal constant BLAST = 0x4300000000000000000000000000000000000002;

    constructor(address recipient, address gasStation) ERC20("Alien", "ALIEN") {
        _mint(recipient, 1_000_000_000 * 10 ** decimals());

        // Blast mainnet
        if (block.chainid == 81457) {
            // Configure gas mode to claimable.
            IBlast(BLAST).configureClaimableGas();
            IBlast(BLAST).configureGovernor(gasStation);
        }
    }

    function mint(address recipient, uint256 amount) external onlyOwner {
        _mint(recipient, amount);
    }
}
