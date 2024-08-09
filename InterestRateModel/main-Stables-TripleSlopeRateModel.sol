/**
 * Submitted for verification at blastscan.io on 2024-03-05
 *
 *
 * 000000000000000000000000000000000000000000000000000000001c59cb9f000000000000000000000000000000000000000000000000000000011b81f43d0000000000000000000000000000000000000000000000000c7d713b49da000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c7d713b49da000000000000000000000000000000000000000000000000000000000016262714cf
 *
 * -----Decoded View---------------
 * Arg [0] : baseRatePerSecond_ (uint256): 475646879
 * Arg [1] : borrowPerSecond1_ (uint256): 4756468797
 * Arg [2] : kink1_ (uint256): 900000000000000000
 * Arg [3] : borrowPerSecond2_ (uint256): 0
 * Arg [4] : kink2_ (uint256): 900000000000000000
 * Arg [5] : borrowPerSecond3_ (uint256): 95129375951
 *
 * -----Encoded View---------------
 * 6 Constructor Arguments found :
 * Arg [0] : 000000000000000000000000000000000000000000000000000000001c59cb9f
 * Arg [1] : 000000000000000000000000000000000000000000000000000000011b81f43d
 * Arg [2] : 0000000000000000000000000000000000000000000000000c7d713b49da0000
 * Arg [3] : 0000000000000000000000000000000000000000000000000000000000000000
 * Arg [4] : 0000000000000000000000000000000000000000000000000c7d713b49da0000
 * Arg [5] : 00000000000000000000000000000000000000000000000000000016262714cf
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// src/interfaces/IInterestRateModel.sol

interface IInterestRateModel {
    function getUtilization(uint256 cash, uint256 borrow) external pure returns (uint256);

    function getBorrowRate(uint256 cash, uint256 borrow) external view returns (uint256);

    function getSupplyRate(uint256 cash, uint256 borrow) external view returns (uint256);
}

// src/protocol/pool/interest-rate-model/TripleSlopeRateModel.sol

contract TripleSlopeRateModel is IInterestRateModel {
    uint256 public immutable baseBorrowPerSecond;
    uint256 public immutable borrowPerSecond1;
    uint256 public immutable kink1;
    uint256 public immutable borrowPerSecond2;
    uint256 public immutable kink2;
    uint256 public immutable borrowPerSecond3;

    constructor(
        uint256 baseRatePerSecond_,
        uint256 borrowPerSecond1_,
        uint256 kink1_,
        uint256 borrowPerSecond2_,
        uint256 kink2_,
        uint256 borrowPerSecond3_
    ) {
        baseBorrowPerSecond = baseRatePerSecond_;
        borrowPerSecond1 = borrowPerSecond1_;
        kink1 = kink1_;
        borrowPerSecond2 = borrowPerSecond2_;
        kink2 = kink2_;
        borrowPerSecond3 = borrowPerSecond3_;
    }

    /**
     * @notice Calculate the utilization rate.
     * @param cash The cash in the market
     * @param borrow The borrow in the market
     * @return The utilization rate
     */
    function getUtilization(uint256 cash, uint256 borrow) public pure returns (uint256) {
        if (borrow == 0) {
            return 0;
        }
        return (borrow * 1e18) / (cash + borrow);
    }

    /**
     * @notice Get the borrow rate per second.
     * @param cash The cash in the market
     * @param borrow The borrow in the market
     * @return The borrow rate per second
     */
    function getBorrowRate(uint256 cash, uint256 borrow) public view returns (uint256) {
        uint256 utilization = getUtilization(cash, borrow);
        if (utilization <= kink1) {
            // base + utilization * slope1
            return baseBorrowPerSecond + (utilization * borrowPerSecond1) / 1e18;
        } else if (utilization <= kink2) {
            // base + kink1 * slope1 + (utilization - kink1) * slope2
            return baseBorrowPerSecond + (kink1 * borrowPerSecond1) / 1e18
                + ((utilization - kink1) * borrowPerSecond2) / 1e18;
        } else {
            // base + kink1 * slope1 + (kink2 - kink1) * slope2 + (utilization - kink2) * slope3
            return baseBorrowPerSecond + (kink1 * borrowPerSecond1) / 1e18 + ((kink2 - kink1) * borrowPerSecond2) / 1e18
                + (utilization - kink2) * borrowPerSecond3 / 1e18;
        }
    }

    /**
     * @notice Get the supply rate per second.
     * @param cash The cash in the market
     * @param borrow The borrow in the market
     * @return The supply rate per second
     */
    function getSupplyRate(uint256 cash, uint256 borrow) public view returns (uint256) {
        uint256 borrowRate = getBorrowRate(cash, borrow);
        uint256 utilization = getUtilization(cash, borrow);
        return (utilization * borrowRate) / 1e18;
    }
}
