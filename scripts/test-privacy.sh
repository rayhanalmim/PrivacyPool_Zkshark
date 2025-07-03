#!/bin/bash

# Exit on error
set -e

echo "=== Testing Privacy System ==="

# Step 1: Compile the circuit
echo "Compiling circuit..."
circom circuits/PrivacyProof.circom --r1cs --wasm --sym -o circuits/build

# Step 2: Generate witness
echo "Generating witness..."
cd circuits/build/PrivacyProof_js
node generate_witness.js PrivacyProof.wasm ../../input.json witness.wtns
cd ../../..

# Step 3: Setup powers of tau
echo "Setting up powers of tau..."
snarkjs powersoftau new bn128 12 circuits/build/pot12_0000.ptau -v
snarkjs powersoftau contribute circuits/build/pot12_0000.ptau circuits/build/pot12_0001.ptau --name="First contribution" -v -e="random"
snarkjs powersoftau prepare phase2 circuits/build/pot12_0001.ptau circuits/build/pot12_final.ptau -v

# Step 4: Generate zkey
echo "Generating zkey..."
snarkjs groth16 setup circuits/build/PrivacyProof.r1cs circuits/build/pot12_final.ptau circuits/build/privacy_0000.zkey
snarkjs zkey contribute circuits/build/privacy_0000.zkey circuits/build/privacy_final.zkey --name="1st Contributor" -e="random"

# Step 5: Export verification key
echo "Exporting verification key..."
snarkjs zkey export verificationkey circuits/build/privacy_final.zkey circuits/build/verification_key.json

# Step 6: Generate Solidity verifier
echo "Generating Solidity verifier..."
snarkjs zkey export solidityverifier circuits/build/privacy_final.zkey src/ZKVerifier.sol

# Step 7: Generate proof
echo "Generating proof..."
snarkjs groth16 prove circuits/build/privacy_final.zkey circuits/build/PrivacyProof_js/witness.wtns circuits/build/proof.json circuits/build/public.json

# Step 8: Verify proof
echo "Verifying proof..."
snarkjs groth16 verify circuits/build/verification_key.json circuits/build/public.json circuits/build/proof.json

echo "=== Test complete! ===" 