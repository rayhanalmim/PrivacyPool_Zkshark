#!/bin/bash

# Create build directory
mkdir -p build

# Compile the circuit
circom circuits/PrivacyProof.circom --r1cs --wasm --sym --c -o build

# Generate the witness generation files
cd build/PrivacyProof_js
node generate_witness.js PrivacyProof.wasm ../input.json witness.wtns

# Start a new powers of tau ceremony
snarkjs powersoftau new bn128 12 pot12_0000.ptau -v

# Contribute to the ceremony
snarkjs powersoftau contribute pot12_0000.ptau pot12_0001.ptau --name="First contribution" -v

# Start generation of phase 2
snarkjs powersoftau prepare phase2 pot12_0001.ptau pot12_final.ptau -v

# Generate zkey
snarkjs groth16 setup ../PrivacyProof.r1cs pot12_final.ptau privacy_0000.zkey

# Contribute to phase 2 of the ceremony
snarkjs zkey contribute privacy_0000.zkey privacy_final.zkey --name="1st Contributor" -v

# Export the verification key
snarkjs zkey export verificationkey privacy_final.zkey verification_key.json

# Generate Solidity verifier
snarkjs zkey export solidityverifier privacy_final.zkey ../../src/ZKVerifier.sol

cd ../..

echo "Circuit compilation and setup complete!" 