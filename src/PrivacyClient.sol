// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PrivacyPool} from "./PrivacyPool.sol";
import {PrivacyUtils} from "./PrivacyUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PrivacyClient
 * @dev A production-ready client interface to make interacting with the privacy pool easier
 * @author SafeSend Team
 * @notice This contract provides user-friendly functions for privacy pool interactions
 */
contract PrivacyClient is ReentrancyGuard, Ownable, Pausable {
    // ═══════════════════════════════ STORAGE ═══════════════════════════════

    PrivacyPool public immutable privacyPool;

    // Client configuration
    uint256 public constant MAX_BATCH_SIZE = 10;
    uint256 public constant MIN_SETUP_DELAY = 1 hours;

    // User management
    mapping(address => bool) public registeredUsers;
    mapping(address => uint256) public userRegistrationTime;
    mapping(address => uint256) public userCommitmentCount;

    // Fee structure (in basis points, 10000 = 100%)
    uint256 public clientFee = 100; // 1% default fee
    uint256 public constant MAX_CLIENT_FEE = 1000; // 10% maximum

    address public feeRecipient;
    uint256 public totalFeesCollected = 0;

    // ═══════════════════════════════ EVENTS ═══════════════════════════════

    event UserRegistered(address indexed user, uint256 timestamp);
    event ReceiverSetup(
        address indexed user,
        uint256 indexed commitment,
        uint256 secretHash, // Hash of secret for privacy
        uint256 timestamp
    );
    event PrivateTransactionSent(
        address indexed sender,
        uint256 indexed commitment,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );
    event BatchCommitmentsGenerated(
        address indexed user,
        uint256 count,
        uint256 timestamp
    );
    event ClientFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newRecipient
    );

    // ═══════════════════════════════ ERRORS ═══════════════════════════════

    error UserNotRegistered();
    error UserAlreadyRegistered();
    error SetupTooEarly();
    error InvalidBatchSize();
    error InvalidFee();
    error InvalidRecipient();
    error InsufficientFee();
    error TransferFailed();

    // ═══════════════════════════════ MODIFIERS ═══════════════════════════════

    modifier onlyRegisteredUser() {
        if (!registeredUsers[msg.sender]) revert UserNotRegistered();
        _;
    }

    modifier validBatchSize(uint256 size) {
        if (size == 0 || size > MAX_BATCH_SIZE) revert InvalidBatchSize();
        _;
    }

    // ═══════════════════════════════ CONSTRUCTOR ═══════════════════════════════

    constructor(
        address payable _privacyPool,
        address _feeRecipient
    ) Ownable(msg.sender) {
        if (_privacyPool == address(0)) revert InvalidRecipient();
        privacyPool = PrivacyPool(_privacyPool);
        feeRecipient = _feeRecipient != address(0) ? _feeRecipient : msg.sender;
    }

    // ═══════════════════════════════ EXTERNAL FUNCTIONS ═══════════════════════════════

    /**
     * @dev Register as a user of the privacy client
     */
    function registerUser() external whenNotPaused {
        if (registeredUsers[msg.sender]) revert UserAlreadyRegistered();

        registeredUsers[msg.sender] = true;
        userRegistrationTime[msg.sender] = block.timestamp;

        emit UserRegistered(msg.sender, block.timestamp);
    }

    /**
     * @dev Set up a receiver with an automatically generated secret
     * Returns the secret and commitment for the user to store securely
     * @param customEntropy Optional custom entropy for secret generation
     * @return secret The generated secret (store securely!)
     * @return commitment The generated commitment (shareable)
     */
    function setupReceiver(
        bytes32 customEntropy
    )
        external
        onlyRegisteredUser
        whenNotPaused
        nonReentrant
        returns (uint256 secret, uint256 commitment)
    {
        // Anti-spam: require delay after registration
        if (
            block.timestamp < userRegistrationTime[msg.sender] + MIN_SETUP_DELAY
        ) {
            revert SetupTooEarly();
        }

        // Generate entropy combining user input with system randomness
        bytes32 entropy = keccak256(
            abi.encodePacked(
                customEntropy,
                msg.sender,
                block.timestamp,
                block.prevrandao,
                userCommitmentCount[msg.sender]
            )
        );

        // Generate secure secret
        secret = PrivacyUtils.generateSecureSecret(entropy);

        // Generate commitment
        commitment = PrivacyUtils.generateCommitment(msg.sender, secret);

        // Register with privacy pool
        privacyPool.registerReceiver(commitment);

        // Update user stats
        userCommitmentCount[msg.sender]++;

        // Emit event with secret hash for privacy
        emit ReceiverSetup(
            msg.sender,
            commitment,
            uint256(keccak256(abi.encodePacked(secret))),
            block.timestamp
        );

        return (secret, commitment);
    }

    /**
     * @dev Set up multiple receivers in batch
     * @param count Number of commitments to generate
     * @param baseEntropy Base entropy for generation
     * @return secrets Array of generated secrets
     * @return commitments Array of generated commitments
     */
    function batchSetupReceivers(
        uint256 count,
        bytes32 baseEntropy
    )
        external
        onlyRegisteredUser
        validBatchSize(count)
        whenNotPaused
        nonReentrant
        returns (uint256[] memory secrets, uint256[] memory commitments)
    {
        if (
            block.timestamp < userRegistrationTime[msg.sender] + MIN_SETUP_DELAY
        ) {
            revert SetupTooEarly();
        }

        secrets = new uint256[](count);
        commitments = new uint256[](count);

        uint256[] memory commitmentsBatch = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            bytes32 entropy = keccak256(
                abi.encodePacked(
                    baseEntropy,
                    msg.sender,
                    block.timestamp,
                    i,
                    userCommitmentCount[msg.sender] + i
                )
            );

            secrets[i] = PrivacyUtils.generateSecureSecret(entropy);
            commitments[i] = PrivacyUtils.generateCommitment(
                msg.sender,
                secrets[i]
            );
            commitmentsBatch[i] = commitments[i];
        }

        // Batch register with privacy pool
        privacyPool.batchRegisterReceivers(commitmentsBatch);

        // Update user stats
        userCommitmentCount[msg.sender] += count;

        emit BatchCommitmentsGenerated(msg.sender, count, block.timestamp);

        return (secrets, commitments);
    }

    /**
     * @dev Send a private transaction to a receiver with fee
     * @param receiverCommitment The receiver's commitment
     */
    function sendPrivateTransaction(
        uint256 receiverCommitment
    ) external payable onlyRegisteredUser whenNotPaused nonReentrant {
        if (msg.value == 0) revert InsufficientFee();
        if (!privacyPool.isValidCommitment(receiverCommitment)) {
            revert InvalidRecipient();
        }

        // Calculate fee
        uint256 fee = (msg.value * clientFee) / 10000;
        uint256 netAmount = msg.value - fee;

        // Send net amount to privacy pool
        privacyPool.deposit{value: netAmount}(receiverCommitment);

        // Collect fee
        if (fee > 0) {
            totalFeesCollected += fee;
            (bool success, ) = feeRecipient.call{value: fee}("");
            if (!success) revert TransferFailed();
        }

        emit PrivateTransactionSent(
            msg.sender,
            receiverCommitment,
            netAmount,
            fee,
            block.timestamp
        );
    }

    /**
     * @dev Send multiple private transactions in batch
     * @param receiverCommitments Array of receiver commitments
     * @param amounts Array of amounts to send (must match commitments length)
     */
    function batchSendPrivateTransactions(
        uint256[] calldata receiverCommitments,
        uint256[] calldata amounts
    )
        external
        payable
        onlyRegisteredUser
        validBatchSize(receiverCommitments.length)
        whenNotPaused
        nonReentrant
    {
        if (receiverCommitments.length != amounts.length)
            revert InvalidBatchSize();

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        uint256 totalFee = (totalAmount * clientFee) / 10000;
        if (msg.value < totalAmount + totalFee) revert InsufficientFee();

        // Process each transaction
        for (uint256 i = 0; i < receiverCommitments.length; i++) {
            if (!privacyPool.isValidCommitment(receiverCommitments[i])) {
                revert InvalidRecipient();
            }

            privacyPool.deposit{value: amounts[i]}(receiverCommitments[i]);

            emit PrivateTransactionSent(
                msg.sender,
                receiverCommitments[i],
                amounts[i],
                (amounts[i] * clientFee) / 10000,
                block.timestamp
            );
        }

        // Handle fee and refund
        totalFeesCollected += totalFee;
        if (totalFee > 0) {
            (bool success, ) = feeRecipient.call{value: totalFee}("");
            if (!success) revert TransferFailed();
        }

        // Refund excess
        uint256 excess = msg.value - totalAmount - totalFee;
        if (excess > 0) {
            (bool success, ) = msg.sender.call{value: excess}("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @dev Generate withdrawal parameters for a receiver
     * This helps users prepare their withdrawal data
     * @param secret The user's secret
     * @param nullifierSecret The nullifier secret
     * @return commitment The generated commitment
     * @return nullifier The generated nullifier
     * @return merkleRoot The current merkle root
     */
    function generateWithdrawalParams(
        uint256 secret,
        uint256 nullifierSecret
    )
        external
        view
        onlyRegisteredUser
        returns (uint256 commitment, bytes32 nullifier, uint256 merkleRoot)
    {
        commitment = PrivacyUtils.generateCommitment(msg.sender, secret);
        nullifier = PrivacyUtils.generateNullifier(
            commitment,
            secret,
            nullifierSecret
        );
        merkleRoot = privacyPool.getMerkleRoot();

        return (commitment, nullifier, merkleRoot);
    }

    // ═══════════════════════════════ VIEW FUNCTIONS ═══════════════════════════════

    /**
     * @dev Check if a nullifier has been used
     * @param nullifier The nullifier to check
     * @return used Whether the nullifier has been used
     */
    function isNullifierUsed(
        bytes32 nullifier
    ) external view returns (bool used) {
        return privacyPool.nullifierUsed(nullifier);
    }

    /**
     * @dev Get comprehensive pool statistics
     * @return stats The pool statistics
     */
    function getPoolStats()
        external
        view
        returns (PrivacyPool.PoolStats memory stats)
    {
        return privacyPool.getPoolStats();
    }

    /**
     * @dev Get user statistics
     * @param user The user address
     * @return isRegistered Whether user is registered
     * @return registrationTime When user registered
     * @return commitmentCount Number of commitments created
     * @return canSetup Whether user can setup new receivers
     */
    function getUserStats(
        address user
    )
        external
        view
        returns (
            bool isRegistered,
            uint256 registrationTime,
            uint256 commitmentCount,
            bool canSetup
        )
    {
        isRegistered = registeredUsers[user];
        registrationTime = userRegistrationTime[user];
        commitmentCount = userCommitmentCount[user];
        canSetup =
            isRegistered &&
            block.timestamp >= registrationTime + MIN_SETUP_DELAY;
    }

    /**
     * @dev Calculate fee for a given amount
     * @param amount The transaction amount
     * @return fee The calculated fee
     * @return netAmount The amount after fee deduction
     */
    function calculateFee(
        uint256 amount
    ) external view returns (uint256 fee, uint256 netAmount) {
        fee = (amount * clientFee) / 10000;
        netAmount = amount - fee;
    }

    // ═══════════════════════════════ ADMIN FUNCTIONS ═══════════════════════════════

    /**
     * @dev Update client fee (only owner)
     * @param newFee The new fee in basis points
     */
    function updateClientFee(uint256 newFee) external onlyOwner {
        if (newFee > MAX_CLIENT_FEE) revert InvalidFee();

        uint256 oldFee = clientFee;
        clientFee = newFee;

        emit ClientFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Update fee recipient (only owner)
     * @param newRecipient The new fee recipient address
     */
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert InvalidRecipient();

        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal of accumulated fees
     */
    function emergencyWithdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = owner().call{value: balance}("");
            if (!success) revert TransferFailed();
        }
    }

    // ═══════════════════════════════ RECEIVE FUNCTION ═══════════════════════════════

    /**
     * @dev Receive function for fee collection
     */
    receive() external payable {
        // Accept direct ETH deposits for fee collection
    }

    /**
     * @dev Fallback function
     */
    fallback() external payable {
        revert("Function not found");
    }
}
