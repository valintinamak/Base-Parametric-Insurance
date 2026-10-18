// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
interface IOmniParametricInsurance {
    function buyInsurancePolicy(uint256 coverageAmountWei, bytes32 conditionsHash) external payable returns (uint256);
    function fileInsuranceClaim(uint256 policyId) external;
}
