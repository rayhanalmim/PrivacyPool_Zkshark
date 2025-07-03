// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PrivacyPool} from "../src/PrivacyPool.sol";
import {ProductionVerifier} from "../src/ProductionVerifier.sol";
import {PrivacyClient} from "../src/PrivacyClient.sol";
import {PrivacyUtils} from "../src/PrivacyUtils.sol";

contract DeployScript is Script {
    PrivacyPool public privacyPool;
    ProductionVerifier public verifier;
    PrivacyClient public client;

    // Deployment configuration
    struct DeployConfig {
        bool useMultisig;
        address multisigOwner;
        address feeRecipient;
        uint256 clientFee;
        bool pauseAfterDeploy;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== SafeSend Production Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Gas Price:", tx.gasprice);

        // Load deployment configuration
        DeployConfig memory config = getDeployConfig();

        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts in correct order
        deployContracts(config);

        // Configure contracts
        configureContracts(config);

        // Verify deployment
        verifyDeployment();

        vm.stopBroadcast();

        // Log deployment summary
        logDeploymentSummary(config);

        // Save deployment addresses
        saveDeploymentInfo();
    }

    function deployContracts(DeployConfig memory config) internal {
        console.log("\n=== Deploying Contracts ===");

        // 1. Deploy ProductionVerifier
        console.log("Deploying ProductionVerifier...");
        verifier = new ProductionVerifier();
        console.log("ProductionVerifier deployed at:", address(verifier));

        // 2. Deploy PrivacyPool
        console.log("Deploying PrivacyPool...");
        privacyPool = new PrivacyPool(address(verifier));
        console.log("PrivacyPool deployed at:", address(privacyPool));

        // 3. Deploy PrivacyClient
        console.log("Deploying PrivacyClient...");
        client = new PrivacyClient(
            payable(address(privacyPool)),
            config.feeRecipient
        );
        console.log("PrivacyClient deployed at:", address(client));

        console.log("All contracts deployed successfully!");
    }

    function configureContracts(DeployConfig memory config) internal {
        console.log("\n=== Configuring Contracts ===");

        // Configure client fee if different from default
        if (config.clientFee != 100) {
            // 100 = 1% default
            console.log(
                "Setting client fee to:",
                config.clientFee,
                "basis points"
            );
            client.updateClientFee(config.clientFee);
        }

        // Transfer ownership to multisig if configured
        if (config.useMultisig && config.multisigOwner != address(0)) {
            console.log(
                "Transferring ownership to multisig:",
                config.multisigOwner
            );

            privacyPool.transferOwnership(config.multisigOwner);
            verifier.transferOwnership(config.multisigOwner);
            client.transferOwnership(config.multisigOwner);

            console.log("Ownership transferred to multisig");
        }

        // Pause contracts if configured (for additional setup)
        if (config.pauseAfterDeploy) {
            console.log("Pausing contracts for additional setup...");
            privacyPool.pause();
            client.pause();
            console.log("Contracts paused");
        }

        console.log("Contract configuration completed!");
    }

    function verifyDeployment() internal view {
        console.log("\n=== Verifying Deployment ===");

        // Verify contract sizes
        require(address(verifier).code.length > 0, "Verifier not deployed");
        require(
            address(privacyPool).code.length > 0,
            "PrivacyPool not deployed"
        );
        require(address(client).code.length > 0, "PrivacyClient not deployed");

        // Verify contract relationships
        require(
            address(privacyPool.verifier()) == address(verifier),
            "PrivacyPool verifier not set correctly"
        );
        require(
            address(client.privacyPool()) == address(privacyPool),
            "PrivacyClient pool not set correctly"
        );

        // Verify initial state
        require(
            privacyPool.getMerkleRoot() != 0,
            "Invalid initial merkle root"
        );
        require(privacyPool.getTreeDepth() == 20, "Invalid tree depth");

        console.log("Deployment verification passed!");
    }

    function logDeploymentSummary(DeployConfig memory config) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Network Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- Verifier:      ", address(verifier));
        console.log("- PrivacyPool:   ", address(privacyPool));
        console.log("- PrivacyClient: ", address(client));
        console.log("");
        console.log("Configuration:");
        console.log(
            "- Multisig Owner:",
            config.useMultisig ? config.multisigOwner : address(0)
        );
        console.log("- Fee Recipient: ", config.feeRecipient);
        console.log("- Client Fee:    ", config.clientFee, "basis points");
        console.log("- Paused:        ", config.pauseAfterDeploy);
        console.log("");
        console.log("Pool Configuration:");
        console.log("- Merkle Root:   ", privacyPool.getMerkleRoot());
        console.log("- Tree Depth:    ", privacyPool.getTreeDepth());
        console.log("- Min Deposit:   ", "0.01 ETH");
        console.log("- Max Deposit:   ", "100 ETH");
        console.log("");
        console.log("Security Features:");
        console.log("- Withdrawal Delay:     1 hour");
        console.log("- Rate Limiting:        10 deposits/day, 10 ETH/day");
        console.log("- Reentrancy Protection: Yes");
        console.log("- Pausable:             Yes");
        console.log("- Access Control:       Yes");

        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Set up monitoring and alerting");
        console.log("3. Configure multisig operations");
        console.log("4. Run integration tests");
        console.log("5. Update frontend with new addresses");

        if (config.pauseAfterDeploy) {
            console.log("6. Unpause contracts when ready for mainnet");
        }
    }

    function saveDeploymentInfo() internal {
        // In a real deployment, you would save this to a file
        // For demonstration, we'll just log the JSON format
        console.log("\n=== Deployment Info (JSON) ===");
        console.log("{");
        console.log('  "chainId":', vm.toString(block.chainid), ",");
        console.log('  "verifier": "', vm.toString(address(verifier)), '",');
        console.log(
            '  "privacyPool": "',
            vm.toString(address(privacyPool)),
            '",'
        );
        console.log('  "privacyClient": "', vm.toString(address(client)), '",');
        console.log('  "blockNumber":', vm.toString(block.number), ",");
        console.log('  "timestamp":', vm.toString(block.timestamp));
        console.log("}");
    }

    function getDeployConfig()
        internal
        view
        returns (DeployConfig memory config)
    {
        // Load configuration from environment variables or use defaults

        // Check if we're on mainnet for production settings
        bool isMainnet = block.chainid == 1;
        bool isTestnet = block.chainid == 5 || block.chainid == 11155111; // Goerli or Sepolia

        if (isMainnet) {
            // Production mainnet configuration
            config = DeployConfig({
                useMultisig: true,
                multisigOwner: vm.envOr("MULTISIG_OWNER", address(0)),
                feeRecipient: vm.envOr(
                    "FEE_RECIPIENT",
                    vm.addr(vm.envUint("PRIVATE_KEY"))
                ),
                clientFee: vm.envOr("CLIENT_FEE", uint256(100)), // 1%
                pauseAfterDeploy: vm.envOr("PAUSE_AFTER_DEPLOY", true)
            });
        } else if (isTestnet) {
            // Testnet configuration
            config = DeployConfig({
                useMultisig: false,
                multisigOwner: address(0),
                feeRecipient: vm.addr(vm.envUint("PRIVATE_KEY")),
                clientFee: 50, // 0.5% for testing
                pauseAfterDeploy: false
            });
        } else {
            // Local/development configuration
            config = DeployConfig({
                useMultisig: false,
                multisigOwner: address(0),
                feeRecipient: vm.addr(vm.envUint("PRIVATE_KEY")),
                clientFee: 0, // No fees for development
                pauseAfterDeploy: false
            });
        }

        // Override with environment variables if set
        if (vm.envOr("USE_MULTISIG", false)) {
            config.useMultisig = true;
            config.multisigOwner = vm.envAddress("MULTISIG_OWNER");
        }

        return config;
    }

    function demonstrateUsage() external view {
        console.log("\n=== Usage Instructions ===");
        console.log("");
        console.log("PRIVACY SETUP (Receiver):");
        console.log("1. Register with client: client.registerUser()");
        console.log("2. Wait 1 hour for anti-spam protection");
        console.log("3. Setup receiver: client.setupReceiver(entropy)");
        console.log("4. Share commitment (not your address!)");
        console.log("");
        console.log("PRIVATE TRANSACTION (Sender):");
        console.log("1. Register with client: client.registerUser()");
        console.log("2. Get receiver's commitment");
        console.log(
            "3. Send: client.sendPrivateTransaction{value: amount}(commitment)"
        );
        console.log("4. Receiver identity is now hidden!");
        console.log("");
        console.log("WITHDRAWAL (Receiver):");
        console.log(
            "1. Generate params: client.generateWithdrawalParams(secret, nullifierSecret)"
        );
        console.log("2. Create zk-SNARK proof using circom circuit");
        console.log("3. Wait withdrawal delay (1 hour)");
        console.log(
            "4. Withdraw: privacyPool.withdraw(proof, nullifier, address, amount)"
        );
        console.log("");
        console.log("MONITORING:");
        console.log("- Pool stats: privacyPool.getPoolStats()");
        console.log("- User stats: client.getUserStats(address)");
        console.log("- Rate limits: privacyPool.checkRateLimits(address)");
        console.log("");
        console.log("PRODUCTION NOTES:");
        console.log(
            "- Replace ProductionVerifier with real circom-generated verifier"
        );
        console.log("- Set up monitoring for contract events");
        console.log("- Configure multisig for admin operations");
        console.log("- Test thoroughly before mainnet deployment");
        console.log("- Consider security audit for production use");
    }
}
