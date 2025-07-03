// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MerkleTree
 * @dev A Merkle tree implementation for storing commitments
 */
library MerkleTree {
    uint256 public constant FIELD_SIZE =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 public constant ZERO_VALUE =
        21663839004416932945382355908790599225266501822907911457504978515578255421292;

    struct Data {
        uint256 levels;
        mapping(uint256 => uint256) filledSubtrees;
        mapping(uint256 => uint256) zeros;
        uint256 currentRootIndex;
        uint256 nextIndex;
        mapping(uint256 => uint256) roots;
    }

    function initialize(Data storage self) internal {
        self.levels = 20; // Depth of 20 should be sufficient

        // Initialize zero values for each level
        self.zeros[0] = ZERO_VALUE;
        for (uint256 i = 1; i < self.levels; i++) {
            self.zeros[i] = hashLeftRight(self.zeros[i - 1], self.zeros[i - 1]);
        }

        // Set initial root
        self.roots[0] = self.zeros[self.levels - 1];
        self.currentRootIndex = 0;
    }

    function hashLeftRight(
        uint256 left,
        uint256 right
    ) internal pure returns (uint256) {
        require(left < FIELD_SIZE, "Left input too large");
        require(right < FIELD_SIZE, "Right input too large");
        return uint256(keccak256(abi.encodePacked(left, right))) % FIELD_SIZE;
    }

    function insert(
        Data storage self,
        uint256 leaf
    ) internal returns (uint256) {
        uint256 currentIndex = self.nextIndex;
        require(currentIndex < 2 ** self.levels, "Merkle tree is full");

        uint256 currentLevelHash = leaf;
        uint256 left;
        uint256 right;

        for (uint256 i = 0; i < self.levels; i++) {
            if (currentIndex % 2 == 0) {
                left = currentLevelHash;
                right = self.zeros[i];
                self.filledSubtrees[i] = currentLevelHash;
            } else {
                left = self.filledSubtrees[i];
                right = currentLevelHash;
            }

            currentLevelHash = hashLeftRight(left, right);
            currentIndex /= 2;
        }

        self.currentRootIndex = (self.currentRootIndex + 1) % 30; // Keep last 30 roots
        self.roots[self.currentRootIndex] = currentLevelHash;

        uint256 insertedIndex = self.nextIndex;
        self.nextIndex++;

        return insertedIndex;
    }

    function getRoot(Data storage self) internal view returns (uint256) {
        return self.roots[self.currentRootIndex];
    }

    function isValidRoot(
        Data storage self,
        uint256 root
    ) internal view returns (bool) {
        if (root == 0) return false;

        // Check last 30 roots
        for (uint256 i = 0; i < 30; i++) {
            if (self.roots[i] == root) return true;
        }
        return false;
    }
}
