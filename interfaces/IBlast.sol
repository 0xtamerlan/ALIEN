// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBlast {
    function configureClaimableGas() external;

    function configureGovernor(address governor) external;

    function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external;

    function claimMaxGas(address contractAddress, address recipientOfGas) external returns (uint256);

    function isGovernor(address contractAddress) external view returns (bool);
}
