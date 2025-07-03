// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVerifier
 * @dev Interface for zk-SNARK proof verification
 * In a real implementation, this would be generated from a circom circuit
 */
interface IVerifier {
    function verifyProof(
        uint256[2] memory _pA,
        uint256[2][2] memory _pB,
        uint256[2] memory _pC,
        uint256[4] memory _pubSignals
    ) external view returns (bool);
}
