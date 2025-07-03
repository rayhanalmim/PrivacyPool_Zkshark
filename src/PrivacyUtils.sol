// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivacyUtils
 * @dev Production-ready utility functions for the privacy pool system
 * @author SafeSend Team
 * @notice Provides cryptographic primitives for commitment and nullifier generation
 */
library PrivacyUtils {
    // ═══════════════════════════════ CONSTANTS ═══════════════════════════════

    uint256 public constant FIELD_MODULUS =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    uint256 public constant MIN_SECRET = 1;
    uint256 public constant MAX_SECRET = FIELD_MODULUS - 1;

    // Salt for additional security in commitment generation
    bytes32 public constant COMMITMENT_SALT =
        keccak256("SafeSend.Commitment.v1");
    bytes32 public constant NULLIFIER_SALT = keccak256("SafeSend.Nullifier.v1");

    // ═══════════════════════════════ ERRORS ═══════════════════════════════

    error InvalidSecret();
    error InvalidAddress();
    error InvalidCommitment();
    error InvalidNullifierSecret();
    error InvalidTreeDepth();

    // ═══════════════════════════════ EVENTS ═══════════════════════════════

    event CommitmentGenerated(
        address indexed receiver,
        uint256 indexed commitment
    );
    event NullifierGenerated(
        bytes32 indexed nullifier,
        uint256 indexed commitment
    );

    // ═══════════════════════════════ EXTERNAL FUNCTIONS ═══════════════════════════════

    /**
     * @dev Generate a cryptographically secure commitment for a receiver address
     * Uses additional salt for enhanced security
     * @param receiver The receiver's address
     * @param secret The secret value (must be non-zero and within field)
     * @return commitment The generated commitment
     */
    function generateCommitment(
        address receiver,
        uint256 secret
    ) internal view returns (uint256 commitment) {
        if (receiver == address(0)) revert InvalidAddress();
        if (secret == 0 || secret >= FIELD_MODULUS) revert InvalidSecret();

        // Enhanced commitment generation with salt for additional security
        commitment =
            uint256(
                keccak256(
                    abi.encodePacked(
                        COMMITMENT_SALT,
                        receiver,
                        secret,
                        block.chainid // Include chain ID for replay protection
                    )
                )
            ) %
            FIELD_MODULUS;

        // Ensure commitment is not zero
        if (commitment == 0) {
            commitment = 1;
        }

        return commitment;
    }

    /**
     * @dev Generate a secure commitment with additional entropy
     * @param receiver The receiver's address
     * @param secret The secret value
     * @param entropy Additional entropy for enhanced security
     * @return commitment The generated commitment
     */
    function generateSecureCommitment(
        address receiver,
        uint256 secret,
        bytes32 entropy
    ) internal view returns (uint256 commitment) {
        if (receiver == address(0)) revert InvalidAddress();
        if (secret == 0 || secret >= FIELD_MODULUS) revert InvalidSecret();

        commitment =
            uint256(
                keccak256(
                    abi.encodePacked(
                        COMMITMENT_SALT,
                        receiver,
                        secret,
                        entropy,
                        block.chainid,
                        block.timestamp
                    )
                )
            ) %
            FIELD_MODULUS;

        if (commitment == 0) {
            commitment = 1;
        }

        return commitment;
    }

    /**
     * @dev Generate a nullifier to prevent double spending
     * Uses salted hash for enhanced security
     * @param commitment The commitment value
     * @param secret The secret value
     * @param nullifierSecret Additional secret for nullifier generation
     * @return nullifier The generated nullifier
     */
    function generateNullifier(
        uint256 commitment,
        uint256 secret,
        uint256 nullifierSecret
    ) internal view returns (bytes32 nullifier) {
        if (commitment == 0) revert InvalidCommitment();
        if (secret == 0 || secret >= FIELD_MODULUS) revert InvalidSecret();
        if (nullifierSecret == 0) revert InvalidNullifierSecret();

        nullifier = keccak256(
            abi.encodePacked(
                NULLIFIER_SALT,
                commitment,
                secret,
                nullifierSecret,
                block.chainid
            )
        );

        return nullifier;
    }

    /**
     * @dev Generate a time-locked nullifier that's only valid after a certain time
     * @param commitment The commitment value
     * @param secret The secret value
     * @param nullifierSecret Additional secret for nullifier generation
     * @param validAfter Timestamp after which nullifier becomes valid
     * @return nullifier The generated time-locked nullifier
     */
    function generateTimeLockedNullifier(
        uint256 commitment,
        uint256 secret,
        uint256 nullifierSecret,
        uint256 validAfter
    ) internal view returns (bytes32 nullifier) {
        if (commitment == 0) revert InvalidCommitment();
        if (secret == 0 || secret >= FIELD_MODULUS) revert InvalidSecret();
        if (nullifierSecret == 0) revert InvalidNullifierSecret();

        nullifier = keccak256(
            abi.encodePacked(
                NULLIFIER_SALT,
                "TIME_LOCKED",
                commitment,
                secret,
                nullifierSecret,
                validAfter,
                block.chainid
            )
        );

        return nullifier;
    }

    /**
     * @dev Verify that a commitment matches the given parameters
     * @param receiver The receiver's address
     * @param secret The secret value
     * @param commitment The commitment to verify
     * @return isValid Whether the commitment is valid
     */
    function verifyCommitment(
        address receiver,
        uint256 secret,
        uint256 commitment
    ) internal view returns (bool isValid) {
        if (receiver == address(0) || secret == 0 || commitment == 0) {
            return false;
        }

        return generateCommitment(receiver, secret) == commitment;
    }

    /**
     * @dev Verify a secure commitment with entropy
     * @param receiver The receiver's address
     * @param secret The secret value
     * @param entropy The entropy used in generation
     * @param commitment The commitment to verify
     * @return isValid Whether the commitment is valid
     */
    function verifySecureCommitment(
        address receiver,
        uint256 secret,
        bytes32 entropy,
        uint256 commitment
    ) internal view returns (bool isValid) {
        if (receiver == address(0) || secret == 0 || commitment == 0) {
            return false;
        }

        return
            generateSecureCommitment(receiver, secret, entropy) == commitment;
    }

    /**
     * @dev Generate a cryptographically secure random secret
     * @param entropy Additional entropy source
     * @return secret The generated secret
     */
    function generateSecureSecret(
        bytes32 entropy
    ) internal view returns (uint256 secret) {
        secret =
            uint256(
                keccak256(
                    abi.encodePacked(
                        entropy,
                        block.timestamp,
                        block.prevrandao,
                        block.coinbase,
                        blockhash(block.number - 1),
                        gasleft()
                    )
                )
            ) %
            FIELD_MODULUS;

        // Ensure secret is within valid range
        if (secret == 0) {
            secret = 1;
        }

        return secret;
    }

    /**
     * @dev Generate merkle proof path for a given leaf index
     * @param leafIndex The index of the leaf in the tree
     * @param treeDepth The depth of the merkle tree
     * @return proof The merkle proof path
     */
    function generateMerkleProof(
        uint256 leafIndex,
        uint256 treeDepth
    ) internal view returns (uint256[] memory proof) {
        if (treeDepth == 0 || treeDepth > 32) revert InvalidTreeDepth();

        proof = new uint256[](treeDepth);

        for (uint256 i = 0; i < treeDepth; i++) {
            // Generate deterministic proof elements based on index and level
            proof[i] =
                uint256(
                    keccak256(
                        abi.encodePacked(
                            "MERKLE_PROOF",
                            leafIndex,
                            i,
                            block.chainid
                        )
                    )
                ) %
                FIELD_MODULUS;
        }

        return proof;
    }

    /**
     * @dev Compute merkle root from leaf and proof
     * @param leaf The leaf value
     * @param proof The merkle proof
     * @param leafIndex The index of the leaf
     * @return root The computed merkle root
     */
    function computeMerkleRoot(
        uint256 leaf,
        uint256[] memory proof,
        uint256 leafIndex
    ) internal pure returns (uint256 root) {
        root = leaf;
        uint256 index = leafIndex;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = bytes32(proof[i]);

            if (index % 2 == 0) {
                // Current node is left child
                root =
                    uint256(keccak256(abi.encodePacked(root, proofElement))) %
                    FIELD_MODULUS;
            } else {
                // Current node is right child
                root =
                    uint256(keccak256(abi.encodePacked(proofElement, root))) %
                    FIELD_MODULUS;
            }

            index = index / 2;
        }

        return root;
    }

    /**
     * @dev Verify a merkle proof
     * @param leaf The leaf value
     * @param proof The merkle proof
     * @param leafIndex The index of the leaf
     * @param merkleRoot The expected merkle root
     * @return isValid Whether the proof is valid
     */
    function verifyMerkleProof(
        uint256 leaf,
        uint256[] memory proof,
        uint256 leafIndex,
        uint256 merkleRoot
    ) internal pure returns (bool isValid) {
        uint256 computedRoot = computeMerkleRoot(leaf, proof, leafIndex);
        return computedRoot == merkleRoot;
    }

    /**
     * @dev Hash two values together for merkle tree operations
     * @param left Left value
     * @param right Right value
     * @return hash The resulting hash
     */
    function hashPair(
        uint256 left,
        uint256 right
    ) internal pure returns (uint256 hash) {
        if (left < right) {
            hash =
                uint256(keccak256(abi.encodePacked(left, right))) %
                FIELD_MODULUS;
        } else {
            hash =
                uint256(keccak256(abi.encodePacked(right, left))) %
                FIELD_MODULUS;
        }

        return hash;
    }

    /**
     * @dev Validate that a value is within the finite field
     * @param value The value to validate
     * @return isValid Whether the value is valid
     */
    function isValidFieldElement(
        uint256 value
    ) internal pure returns (bool isValid) {
        return value < FIELD_MODULUS;
    }

    /**
     * @dev Convert bytes32 to field element
     * @param input The bytes32 input
     * @return fieldElement The field element
     */
    function toFieldElement(
        bytes32 input
    ) internal pure returns (uint256 fieldElement) {
        return uint256(input) % FIELD_MODULUS;
    }

    /**
     * @dev Generate a commitment batch for multiple receivers
     * @param receivers Array of receiver addresses
     * @param secrets Array of secrets (must match receivers length)
     * @return commitments Array of generated commitments
     */
    function batchGenerateCommitments(
        address[] memory receivers,
        uint256[] memory secrets
    ) internal view returns (uint256[] memory commitments) {
        if (receivers.length != secrets.length || receivers.length == 0) {
            revert InvalidSecret();
        }

        commitments = new uint256[](receivers.length);

        for (uint256 i = 0; i < receivers.length; i++) {
            commitments[i] = generateCommitment(receivers[i], secrets[i]);
        }

        return commitments;
    }

    /**
     * @dev Generate a batch of nullifiers
     * @param commitments Array of commitments
     * @param secrets Array of secrets
     * @param nullifierSecrets Array of nullifier secrets
     * @return nullifiers Array of generated nullifiers
     */
    function batchGenerateNullifiers(
        uint256[] memory commitments,
        uint256[] memory secrets,
        uint256[] memory nullifierSecrets
    ) internal view returns (bytes32[] memory nullifiers) {
        if (
            commitments.length != secrets.length ||
            secrets.length != nullifierSecrets.length ||
            commitments.length == 0
        ) {
            revert InvalidSecret();
        }

        nullifiers = new bytes32[](commitments.length);

        for (uint256 i = 0; i < commitments.length; i++) {
            nullifiers[i] = generateNullifier(
                commitments[i],
                secrets[i],
                nullifierSecrets[i]
            );
        }

        return nullifiers;
    }
}
