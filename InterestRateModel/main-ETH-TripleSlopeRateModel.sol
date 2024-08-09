/**
 * Submitted for verification at blastscan.io on 2024-03-05
 *
 *
 * BYTECODE
 * 0x608060405234801561001057600080fd5b50600436106100935760003560e01c806346dda3581161006657806346dda3581461013257806350af8cd614610145578063a5cdfa941461016c578063d34f61141461017f578063e3a6fe25146101a657600080fd5b8063158e9c4a146100985780632a11a8a0146100d15780632f1f2c42146100e4578063382be1cd1461010b575b600080fd5b6100bf7f000000000000000000000000000000000000000000000000000000000000000081565b60405190815260200160405180910390f35b6100bf6100df366004610594565b6101cd565b6100bf7f00000000000000000000000000000000000000000000000000000000097343df81565b6100bf7f0000000000000000000000000000000000000000000000000000000071672e7f81565b6100bf610140366004610594565b610212565b6100bf7f00000000000000000000000000000000000000000000000009b6e64a8ec6000081565b6100bf61017a366004610594565b61024e565b6100bf7f00000000000000000000000000000000000000000000000009b6e64a8ec6000081565b6100bf7f00000000000000000000000000000000000000000000000000000007620d06ef81565b6000806101da848461024e565b905060006101e88585610212565b9050670de0b6b3a76400006101fd83836105cc565b61020791906105eb565b925050505b92915050565b6000816102215750600061020c565b61022b828461060d565b61023d83670de0b6b3a76400006105cc565b61024791906105eb565b9392505050565b60008061025b8484610212565b90507f00000000000000000000000000000000000000000000000009b6e64a8ec6000081116102f357670de0b6b3a76400006102b77f0000000000000000000000000000000000000000000000000000000071672e7f836105cc565b6102c191906105eb565b6102eb907f00000000000000000000000000000000000000000000000000000000097343df61060d565b91505061020c565b7f00000000000000000000000000000000000000000000000009b6e64a8ec60000811161041357670de0b6b3a76400007f000000000000000000000000000000000000000000000000000000000000000061036e7f00000000000000000000000000000000000000000000000009b6e64a8ec6000084610625565b61037891906105cc565b61038291906105eb565b670de0b6b3a76400006103d57f0000000000000000000000000000000000000000000000000000000071672e7f7f00000000000000000000000000000000000000000000000009b6e64a8ec600006105cc565b6103df91906105eb565b610409907f00000000000000000000000000000000000000000000000000000000097343df61060d565b6102eb919061060d565b670de0b6b3a76400007f00000000000000000000000000000000000000000000000000000007620d06ef6104677f00000000000000000000000000000000000000000000000009b6e64a8ec6000084610625565b61047191906105cc565b61047b91906105eb565b670de0b6b3a76400007f00000000000000000000000000000000000000000000000000000000000000006104ef7f00000000000000000000000000000000000000000000000009b6e64a8ec600007f00000000000000000000000000000000000000000000000009b6e64a8ec60000610625565b6104f991906105cc565b61050391906105eb565b670de0b6b3a76400006105567f0000000000000000000000000000000000000000000000000000000071672e7f7f00000000000000000000000000000000000000000000000009b6e64a8ec600006105cc565b61056091906105eb565b61058a907f00000000000000000000000000000000000000000000000000000000097343df61060d565b610409919061060d565b600080604083850312156105a757600080fd5b50508035926020909101359150565b634e487b7160e01b600052601160045260246000fd5b60008160001904831182151516156105e6576105e66105b6565b500290565b60008261060857634e487b7160e01b600052601260045260246000fd5b500490565b60008219821115610620576106206105b6565b500190565b600082821015610637576106376105b6565b50039056fea26469706673582212205cbd4a41e73844801307fad05d7960d40efeefbeebe0b03f8e961a8fbcf3a72a64736f6c634300080a0033
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
