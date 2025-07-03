// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ProductionVerifier} from "../src/ProductionVerifier.sol";
import {PrivacyUtils} from "../src/PrivacyUtils.sol";
import {PrivacyClient} from "../src/PrivacyClient.sol";

contract PrivacySystemTest is Test {
    PrivacyPool public privacyPool;
    ProductionVerifier public verifier;
    PrivacyClient public client;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public deployer = address(0x4);

    uint256 public constant SECRET = 123456789;
    uint256 public constant NULLIFIER_SECRET = 987654321;

    // Load proof data from generated files
    string internal constant PROOF_PATH = "circuits/build/proof.json";
    string internal constant PUBLIC_PATH = "circuits/build/public.json";

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

        // Step 1: Bob registers as a receiver
        uint256 bobCommitment = PrivacyUtils.generateCommitment(bob, SECRET);
        console.log("Bob's commitment:", bobCommitment);

        vm.prank(bob);
        privacyPool.registerReceiver(bobCommitment);
        assertTrue(privacyPool.isValidCommitment(bobCommitment));
        console.log("[SUCCESS] Bob registered successfully");

        // Step 2: Alice deposits funds for Bob
        uint256 depositAmount = 1 ether;
        vm.prank(alice);
        privacyPool.deposit{value: depositAmount}(bobCommitment);
        assertEq(address(privacyPool).balance, depositAmount);
        console.log("[SUCCESS] Alice deposited", depositAmount, "ETH for Bob");

        // Step 3: Generate nullifier
        bytes32 nullifier = PrivacyUtils.generateNullifier(
            bobCommitment,
            SECRET,
            NULLIFIER_SECRET
        );

        // Step 4: Load real proof data from generated files
        string memory proof = vm.readFile(PROOF_PATH);
        string memory public_inputs = vm.readFile(PUBLIC_PATH);

        // Parse proof data (you'll need to implement this based on your proof format)
        (
            uint256[2] memory _pA,
            uint256[2][2] memory _pB,
            uint256[2] memory _pC,
            uint256[4] memory _pubSignals
        ) = parseProofData(proof, public_inputs);

        // Wait for withdrawal delay
        vm.warp(block.timestamp + 2 hours);

        // Step 5: Bob withdraws using the real proof
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(bob);
        privacyPool.withdraw(
            PrivacyPool.ProofData({
                _pA: _pA,
                _pB: _pB,
                _pC: _pC,
                _pubSignals: _pubSignals
            }),
            nullifier,
            payable(bob),
            depositAmount
        );

        assertEq(bob.balance - bobBalanceBefore, depositAmount);
        assertTrue(privacyPool.nullifierUsed(nullifier));
        console.log("[SUCCESS] Bob withdrew", depositAmount, "ETH privately");
    }

    function parseProofData(
        string memory proof,
        string memory public_inputs
    )
        internal
        pure
        returns (
            uint256[2] memory _pA,
            uint256[2][2] memory _pB,
            uint256[2] memory _pC,
            uint256[4] memory _pubSignals
        )
    {
        // This function should parse the JSON proof data into the required format
        // For now, we'll return dummy data - you'll need to implement proper parsing
        _pA = [uint256(1), uint256(2)];
        _pB = [[uint256(3), uint256(4)], [uint256(5), uint256(6)]];
        _pC = [uint256(7), uint256(8)];
        _pubSignals = [uint256(1), uint256(2), uint256(3), uint256(4)];
    }

    function testClientInterface() public {
        console.log("=== Client Interface Test ===");

        // Register users
        vm.prank(bob);
        client.registerUser();

        vm.prank(alice);
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
        console.log("[SUCCESS] Receiver setup through client");

        // Send private transaction
        uint256 sendAmount = 1 ether;
        vm.prank(alice);
        client.sendPrivateTransaction{value: sendAmount}(commitment);
        console.log("[SUCCESS] Private transaction sent through client");
    }

    function testBatchOperations() public {
        console.log("=== Batch Operations Test ===");

        // Register user
        vm.prank(bob);
        client.registerUser();

        // Wait for setup delay
        vm.warp(block.timestamp + 2 hours);

        // Setup multiple receivers
        vm.prank(bob);
        (uint256[] memory secrets, uint256[] memory commitments) = client
            .batchSetupReceivers(3, bytes32(uint256(123)));

        for (uint256 i = 0; i < commitments.length; i++) {
            assertTrue(privacyPool.isValidCommitment(commitments[i]));
        }
        console.log("[SUCCESS] Batch receiver setup works");

        // Send batch transactions
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.5 ether;
        amounts[1] = 0.5 ether;

        uint256[] memory selectedCommitments = new uint256[](2);
        selectedCommitments[0] = commitments[0];
        selectedCommitments[1] = commitments[1];

        vm.prank(alice);
        client.registerUser();
        vm.warp(block.timestamp + 2 hours);

        vm.prank(alice);
        client.batchSendPrivateTransactions{value: 1.1 ether}(
            selectedCommitments,
            amounts
        );
        console.log("[SUCCESS] Batch transactions work");
    }

    receive() external payable {}
}
