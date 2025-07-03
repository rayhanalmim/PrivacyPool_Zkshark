// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ProductionVerifier} from "../src/ProductionVerifier.sol";
import {PrivacyUtils} from "../src/PrivacyUtils.sol";
import {PrivacyClient} from "../src/PrivacyClient.sol";

contract PrivacyPoolTest is Test {
    PrivacyPool public privacyPool;
    ProductionVerifier public verifier;
    PrivacyClient public client;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public deployer = address(0x4);

    uint256 public constant SECRET = 12345;
    uint256 public constant NULLIFIER_SECRET = 67890;

    event ReceiverRegistered(
        uint256 indexed commitment,
        address indexed receiver,
        uint256 timestamp
    );

    event Deposit(
        uint256 indexed commitment,
        uint256 indexed leafIndex,
        uint256 amount,
        address indexed sender
    );

    event Withdrawal(
        bytes32 indexed nullifier,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy verifier first
        verifier = new ProductionVerifier();

        // Deploy privacy pool
        privacyPool = new PrivacyPool(address(verifier));

        // Deploy client
        client = new PrivacyClient(payable(address(privacyPool)), deployer);

        vm.stopPrank();

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 5 ether);
        vm.deal(charlie, 5 ether);
        vm.deal(deployer, 1 ether);
    }

    function testCompletePrivacyFlow() public {
        console.log("=== Complete Privacy Flow Test ===");

        // Step 1: Bob registers as a receiver (generates commitment)
        uint256 bobCommitment = PrivacyUtils.generateCommitment(bob, SECRET);
        console.log("Bob's commitment:", bobCommitment);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit ReceiverRegistered(bobCommitment, bob, block.timestamp);
        privacyPool.registerReceiver(bobCommitment);

        assertTrue(privacyPool.isValidCommitment(bobCommitment));
        console.log("[SUCCESS] Bob registered successfully");

        // Step 2: Alice deposits funds for Bob (using Bob's commitment)
        uint256 depositAmount = 1 ether;

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Deposit(bobCommitment, 0, depositAmount, alice);
        privacyPool.deposit{value: depositAmount}(bobCommitment);

        assertEq(address(privacyPool).balance, depositAmount);
        console.log(
            "[SUCCESS] Alice deposited",
            depositAmount,
            "ETH for Bob privately"
        );

        // Step 3: Bob withdraws the funds using a zk-SNARK proof
        bytes32 nullifier = PrivacyUtils.generateNullifier(
            bobCommitment,
            SECRET,
            NULLIFIER_SECRET
        );

        // Create proof data
        PrivacyPool.ProofData memory proof = PrivacyPool.ProofData({
            _pA: [uint256(1), uint256(2)],
            _pB: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            _pC: [uint256(7), uint256(8)],
            _pubSignals: [
                uint256(nullifier),
                bobCommitment,
                depositAmount,
                privacyPool.getMerkleRoot()
            ]
        });

        uint256 bobBalanceBefore = bob.balance;

        // Wait for withdrawal delay
        vm.warp(block.timestamp + 2 hours);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Withdrawal(nullifier, bob, depositAmount, block.timestamp);
        privacyPool.withdraw(proof, nullifier, payable(bob), depositAmount);

        assertEq(bob.balance - bobBalanceBefore, depositAmount);
        assertTrue(privacyPool.nullifierUsed(nullifier));
        console.log("[SUCCESS] Bob withdrew", depositAmount, "ETH privately");

        console.log("[COMPLETE] Privacy flow completed successfully!");
    }

    function testDoubleSpendingPrevention() public {
        console.log("=== Double Spending Prevention Test ===");

        // Setup
        uint256 commitment = PrivacyUtils.generateCommitment(bob, SECRET);
        vm.prank(bob);
        privacyPool.registerReceiver(commitment);

        vm.prank(alice);
        privacyPool.deposit{value: 1 ether}(commitment);

        bytes32 nullifier = PrivacyUtils.generateNullifier(
            commitment,
            SECRET,
            NULLIFIER_SECRET
        );

        PrivacyPool.ProofData memory proof = PrivacyPool.ProofData({
            _pA: [uint256(1), uint256(2)],
            _pB: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            _pC: [uint256(7), uint256(8)],
            _pubSignals: [
                uint256(nullifier),
                commitment,
                1 ether,
                privacyPool.getMerkleRoot()
            ]
        });

        // Wait for withdrawal delay
        vm.warp(block.timestamp + 2 hours);

        // First withdrawal should succeed
        vm.prank(bob);
        privacyPool.withdraw(proof, nullifier, payable(bob), 1 ether);
        console.log("[SUCCESS] First withdrawal successful");

        // Second withdrawal with same nullifier should fail
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NullifierAlreadyUsed()"));
        privacyPool.withdraw(proof, nullifier, payable(bob), 1 ether);
        console.log("[SUCCESS] Double spending prevented");
    }

    function testMultipleReceivers() public {
        console.log("=== Multiple Receivers Test ===");

        // Register multiple receivers
        uint256 bobCommitment = PrivacyUtils.generateCommitment(bob, SECRET);
        uint256 charlieCommitment = PrivacyUtils.generateCommitment(
            charlie,
            SECRET + 1
        );

        vm.prank(bob);
        privacyPool.registerReceiver(bobCommitment);

        vm.prank(charlie);
        privacyPool.registerReceiver(charlieCommitment);

        console.log("[SUCCESS] Multiple receivers registered");

        // Alice sends to both
        vm.prank(alice);
        privacyPool.deposit{value: 1 ether}(bobCommitment);

        vm.prank(alice);
        privacyPool.deposit{value: 0.5 ether}(charlieCommitment);

        assertEq(address(privacyPool).balance, 1.5 ether);
        console.log("[SUCCESS] Alice sent to multiple receivers privately");

        // Both can withdraw
        bytes32 bobNullifier = PrivacyUtils.generateNullifier(
            bobCommitment,
            SECRET,
            NULLIFIER_SECRET
        );
        bytes32 charlieNullifier = PrivacyUtils.generateNullifier(
            charlieCommitment,
            SECRET + 1,
            NULLIFIER_SECRET
        );

        PrivacyPool.ProofData memory bobProof = PrivacyPool.ProofData({
            _pA: [uint256(1), uint256(2)],
            _pB: [[uint256(3), uint256(4)], [uint256(5), uint256(6)]],
            _pC: [uint256(7), uint256(8)],
            _pubSignals: [
                uint256(bobNullifier),
                bobCommitment,
                1 ether,
                privacyPool.getMerkleRoot()
            ]
        });

        // Wait for withdrawal delay
        vm.warp(block.timestamp + 2 hours);

        vm.prank(bob);
        privacyPool.withdraw(bobProof, bobNullifier, payable(bob), 1 ether);
        console.log("[SUCCESS] Bob withdrew his funds");

        PrivacyPool.ProofData memory charlieProof = PrivacyPool.ProofData({
            _pA: [uint256(10), uint256(20)],
            _pB: [[uint256(30), uint256(40)], [uint256(50), uint256(60)]],
            _pC: [uint256(70), uint256(80)],
            _pubSignals: [
                uint256(charlieNullifier),
                charlieCommitment,
                0.5 ether,
                privacyPool.getMerkleRoot()
            ]
        });

        vm.prank(charlie);
        privacyPool.withdraw(
            charlieProof,
            charlieNullifier,
            payable(charlie),
            0.5 ether
        );
        console.log("[SUCCESS] Charlie withdrew his funds");
    }

    function testInvalidProofRejection() public {
        console.log("=== Invalid Proof Rejection Test ===");

        uint256 commitment = PrivacyUtils.generateCommitment(bob, SECRET);
        vm.prank(bob);
        privacyPool.registerReceiver(commitment);

        vm.prank(alice);
        privacyPool.deposit{value: 1 ether}(commitment);

        // Create invalid proof (all zeros)
        PrivacyPool.ProofData memory invalidProof = PrivacyPool.ProofData({
            _pA: [uint256(0), uint256(0)],
            _pB: [[uint256(0), uint256(0)], [uint256(0), uint256(0)]],
            _pC: [uint256(0), uint256(0)],
            _pubSignals: [uint256(0), uint256(0), uint256(0), uint256(0)]
        });

        bytes32 nullifier = PrivacyUtils.generateNullifier(
            commitment,
            SECRET,
            NULLIFIER_SECRET
        );

        // Wait for withdrawal delay
        vm.warp(block.timestamp + 2 hours);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        privacyPool.withdraw(invalidProof, nullifier, payable(bob), 1 ether);
        console.log("[SUCCESS] Invalid proof rejected");
    }

    function testRateLimiting() public {
        console.log("=== Rate Limiting Test ===");

        uint256 commitment = PrivacyUtils.generateCommitment(bob, SECRET);
        vm.prank(bob);
        privacyPool.registerReceiver(commitment);

        // Try to exceed daily deposit limit
        vm.startPrank(alice);

        // Should succeed up to limit
        for (uint256 i = 0; i < 10; i++) {
            privacyPool.deposit{value: 1 ether}(commitment);
        }

        // 11th deposit should fail
        vm.expectRevert(abi.encodeWithSignature("RateLimitExceeded()"));
        privacyPool.deposit{value: 1 ether}(commitment);

        vm.stopPrank();
        console.log("[SUCCESS] Rate limiting works correctly");
    }

    function testBatchOperations() public {
        console.log("=== Batch Operations Test ===");

        // Test batch registration
        uint256[] memory commitments = new uint256[](3);
        commitments[0] = PrivacyUtils.generateCommitment(bob, SECRET);
        commitments[1] = PrivacyUtils.generateCommitment(bob, SECRET + 1);
        commitments[2] = PrivacyUtils.generateCommitment(bob, SECRET + 2);

        vm.prank(bob);
        privacyPool.batchRegisterReceivers(commitments);

        // Verify all commitments are registered
        for (uint256 i = 0; i < commitments.length; i++) {
            assertTrue(privacyPool.isValidCommitment(commitments[i]));
        }

        console.log("[SUCCESS] Batch registration works");
    }

    function testClientInterface() public {
        console.log("=== Client Interface Test ===");

        // Register user
        vm.prank(bob);
        client.registerUser();

        // Wait for setup delay
        vm.warp(block.timestamp + 2 hours);

        // Setup receiver
        vm.prank(bob);
        (uint256 secret, uint256 commitment) = client.setupReceiver(
            bytes32(uint256(123))
        );

        assertTrue(secret != 0);
        assertTrue(commitment != 0);
        assertTrue(privacyPool.isValidCommitment(commitment));

        console.log("[SUCCESS] Client interface works");

        // Send private transaction with fee
        uint256 sendAmount = 1 ether;
        uint256 fee = (sendAmount * 100) / 10000; // 1% fee

        vm.prank(alice);
        client.registerUser();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(alice);
        client.sendPrivateTransaction{value: sendAmount}(commitment);

        // Check that fee was deducted
        assertEq(address(privacyPool).balance, sendAmount - fee);
        console.log("[SUCCESS] Client fee mechanism works");
    }

    function testPoolStatistics() public {
        console.log("=== Pool Statistics Test ===");

        uint256 commitment = PrivacyUtils.generateCommitment(bob, SECRET);
        vm.prank(bob);
        privacyPool.registerReceiver(commitment);

        vm.prank(alice);
        privacyPool.deposit{value: 1 ether}(commitment);

        PrivacyPool.PoolStats memory stats = privacyPool.getPoolStats();

        assertEq(stats.totalDeposited, 1 ether);
        assertEq(stats.currentBalance, 1 ether);
        assertEq(stats.totalCommitments, 1);
        assertTrue(stats.merkleRoot != 0);

        console.log("[SUCCESS] Pool statistics are accurate");
    }

    function testPrivacyUtilsFunctions() public {
        console.log("=== Privacy Utils Test ===");

        // Test commitment generation
        uint256 commitment1 = PrivacyUtils.generateCommitment(bob, SECRET);
        uint256 commitment2 = PrivacyUtils.generateCommitment(bob, SECRET);
        uint256 commitment3 = PrivacyUtils.generateCommitment(charlie, SECRET);

        assertEq(commitment1, commitment2);
        assertNotEq(commitment1, commitment3);
        console.log("[SUCCESS] Commitment generation works correctly");

        // Test commitment verification
        assertTrue(PrivacyUtils.verifyCommitment(bob, SECRET, commitment1));
        assertFalse(
            PrivacyUtils.verifyCommitment(charlie, SECRET, commitment1)
        );
        console.log("[SUCCESS] Commitment verification works correctly");

        // Test nullifier generation
        bytes32 nullifier1 = PrivacyUtils.generateNullifier(
            commitment1,
            SECRET,
            NULLIFIER_SECRET
        );
        bytes32 nullifier2 = PrivacyUtils.generateNullifier(
            commitment1,
            SECRET,
            NULLIFIER_SECRET
        );
        bytes32 nullifier3 = PrivacyUtils.generateNullifier(
            commitment1,
            SECRET,
            NULLIFIER_SECRET + 1
        );

        assertEq(nullifier1, nullifier2);
        assertNotEq(nullifier1, nullifier3);
        console.log("[SUCCESS] Nullifier generation works correctly");
    }

    function testMerkleTreeIntegration() public {
        console.log("=== Merkle Tree Integration Test ===");

        uint256 initialRoot = privacyPool.getMerkleRoot();
        console.log("Initial merkle root:", initialRoot);

        // Register a receiver (adds to merkle tree)
        uint256 commitment = PrivacyUtils.generateCommitment(bob, SECRET);
        vm.prank(bob);
        privacyPool.registerReceiver(commitment);

        uint256 newRoot = privacyPool.getMerkleRoot();
        assertNotEq(initialRoot, newRoot);
        console.log("New merkle root after registration:", newRoot);
        console.log("[SUCCESS] Merkle tree updates correctly");
    }

    function testAccessControls() public {
        console.log("=== Access Controls Test ===");

        // Test pause functionality
        vm.prank(deployer);
        privacyPool.pause();

        uint256 commitment = PrivacyUtils.generateCommitment(bob, SECRET);

        // Should fail when paused
        vm.prank(bob);
        vm.expectRevert("Pausable: paused");
        privacyPool.registerReceiver(commitment);

        // Unpause
        vm.prank(deployer);
        privacyPool.unpause();

        // Should work after unpause
        vm.prank(bob);
        privacyPool.registerReceiver(commitment);

        assertTrue(privacyPool.isValidCommitment(commitment));
        console.log("[SUCCESS] Access controls work correctly");
    }

    function testEmergencyFunctions() public {
        console.log("=== Emergency Functions Test ===");

        // Fund the pool
        vm.deal(address(privacyPool), 5 ether);

        uint256 ownerBalanceBefore = deployer.balance;

        // Test emergency withdrawal
        vm.prank(deployer);
        privacyPool.emergencyWithdraw(1 ether);

        assertEq(deployer.balance - ownerBalanceBefore, 1 ether);
        console.log("[SUCCESS] Emergency withdrawal works");
    }

    receive() external payable {}
}
