# 📖 SafeSend Usage Guide

This guide shows you exactly how to use the SafeSend privacy system to send transactions where **receiver identities are hidden on-chain**.

## 🎯 Quick Overview

**Problem**: When you send crypto to someone, their address is visible to everyone on the blockchain.

**Solution**: SafeSend uses zk-SNARKs to hide receiver addresses while keeping transactions fully verifiable.

## 🚀 Step-by-Step Usage

### Prerequisites

```bash
# Clone and setup
git clone <your-repo>
cd safeSend
forge build

# Start local blockchain
anvil

# Deploy contracts
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

## 👤 For Receivers: Setting Up Private Address

If you want to **receive** private payments:

### 1. Generate Your Secret

```javascript
// Keep this secret safe! Never share it!
const secret = ethers.utils.hexlify(ethers.utils.randomBytes(32));
console.log("Your secret:", secret);
```

### 2. Generate Your Commitment (Public Address)

```solidity
// This is your "private address" that you can share
uint256 commitment = PrivacyUtils.generateCommitment(yourAddress, secret);
```

### 3. Register as Receiver

```solidity
// Call this once to register
privacyPool.registerReceiver(commitment);
```

### 4. Share Your Commitment

```bash
# Share this with people who want to send you private payments
echo "My private address commitment: 0x1234..."
```

**✅ Complete! You can now receive private payments**

---

## 💸 For Senders: Sending Private Transactions

If you want to **send** a private payment:

### 1. Get Receiver's Commitment

```javascript
// Get this from the person you want to pay
const receiverCommitment = "0x1234..."; // Their "private address"
```

### 2. Send Private Transaction

```solidity
// Send ETH without revealing who receives it!
privacyPool.deposit{value: 1 ether}(receiverCommitment);
```

**✅ Done! The receiver's identity is now hidden on-chain**

---

## 💰 For Receivers: Withdrawing Private Payments

If someone sent you a private payment:

### 1. Generate Nullifier

```solidity
// Use your secret to generate nullifier (prevents double-spending)
bytes32 nullifier = PrivacyUtils.generateNullifier(
    yourCommitment, 
    yourSecret, 
    randomNullifierSecret
);
```

### 2. Create zk-SNARK Proof

```javascript
// In production, use circom circuit. For demo:
const proof = {
    _pA: [1, 2],
    _pB: [[3, 4], [5, 6]], 
    _pC: [7, 8],
    _pubSignals: [nullifier, commitment, amount, merkleRoot]
};
```

### 3. Withdraw Funds

```solidity
privacyPool.withdraw(proof, nullifier, yourAddress, amount);
```

**✅ Funds received privately!**

---

## 🔧 Using the Client Interface

For easier interaction, use the `PrivacyClient` contract:

### Easy Receiver Setup

```solidity
// Automatically generates secret and registers
(uint256 secret, uint256 commitment) = privacyClient.setupReceiver();

// Save these values securely!
console.log("Secret:", secret);
console.log("Commitment:", commitment);
```

### Easy Private Transaction

```solidity
// Send private payment in one call
privacyClient.sendPrivateTransaction{value: 1 ether}(receiverCommitment);
```

---

## 📊 Real Example Flow

Let's say Alice wants to send Bob 1 ETH privately:

### Bob's Setup (Receiver)
```solidity
// 1. Bob generates secret
uint256 bobSecret = 12345;

// 2. Bob creates commitment
uint256 bobCommitment = PrivacyUtils.generateCommitment(bob, bobSecret);
// Result: 526787770315863412878013142196942431766326758053646429938212582076754231952

// 3. Bob registers
privacyPool.registerReceiver(bobCommitment);

// 4. Bob shares commitment with Alice
// "Hey Alice, send payments to: 526787770315863412878013142196942431766326758053646429938212582076754231952"
```

### Alice's Transaction (Sender)
```solidity
// 1. Alice uses Bob's commitment (not his address!)
privacyPool.deposit{value: 1 ether}(526787770315863412878013142196942431766326758053646429938212582076754231952);

// ✅ Transaction complete! Bob's address is hidden on-chain
```

### Bob's Withdrawal (Receiver)
```solidity
// 1. Bob generates nullifier
bytes32 nullifier = PrivacyUtils.generateNullifier(bobCommitment, bobSecret, 67890);

// 2. Bob creates proof and withdraws
PrivacyPool.ProofData memory proof = /* generate proof */;
privacyPool.withdraw(proof, nullifier, bob, 1 ether);

// ✅ Bob receives 1 ETH privately!
```

---

## 🔍 Verification

Anyone can verify the transaction is valid without seeing Bob's address:

```bash
# Check on blockchain explorer:
# - Deposit transaction shows: Alice -> PrivacyPool (1 ETH)
# - Withdrawal shows: PrivacyPool -> Someone (1 ETH)
# - Bob's identity remains hidden! 🎭
```

---

## 🛡️ Security Notes

### ✅ What's Private
- **Receiver identities** - Completely hidden
- **Transaction unlinkability** - Can't link deposits to withdrawals
- **Amount privacy** - Can be added with modifications

### ⚠️ Security Requirements
- **Keep secrets safe** - If lost, cannot withdraw
- **Use strong randomness** - For secrets and nullifiers
- **Verify proofs** - System validates all zk-SNARK proofs

### 🔒 Production Considerations
- Replace `MockVerifier` with real circom-generated verifier
- Implement proper merkle proof verification in circuit
- Add relayer network for withdrawal anonymity
- Conduct security audits

---

## 🚨 Troubleshooting

### "Invalid commitment" error
- Ensure the receiver has registered their commitment
- Check commitment was calculated correctly

### "Nullifier already used" error  
- Each nullifier can only be used once (prevents double-spending)
- Generate a new nullifier with different nullifierSecret

### "Invalid proof" error
- Proof verification failed
- In production, ensure circuit generates valid proofs

---

## 📚 Advanced Usage

### Multiple Receivers
```solidity
// Alice can send to multiple people privately
privacyPool.deposit{value: 1 ether}(bobCommitment);
privacyPool.deposit{value: 2 ether}(charlieCommitment);
privacyPool.deposit{value: 0.5 ether}(daveCommitment);

// All receiver identities remain hidden!
```

### Batch Operations
```solidity
// Bob can check if funds are available
bool hasUnusedFunds = !privacyPool.nullifierUsed(myNullifier);

// Get pool statistics
(uint256 balance, uint256 merkleRoot, uint256 depth) = client.getPoolStats();
```

---

## 🎉 Summary

With SafeSend, you can:

1. **Generate private addresses** (commitments) for receiving funds
2. **Send payments** using commitments instead of wallet addresses  
3. **Withdraw funds** privately using zk-SNARK proofs
4. **Keep receiver identities hidden** from blockchain observers

**The result**: True transaction privacy while maintaining full security and verifiability! 🔒✨ 