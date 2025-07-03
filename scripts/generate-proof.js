const snarkjs = require("snarkjs");
const fs = require("fs");

async function generateProof(inputs) {
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        inputs,
        "build/PrivacyProof_js/PrivacyProof.wasm",
        "build/privacy_final.zkey"
    );

    // Convert proof to contract format
    const proofForContract = {
        _pA: [proof.pi_a[0], proof.pi_a[1]],
        _pB: [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]],
        _pC: [proof.pi_c[0], proof.pi_c[1]],
        _pubSignals: publicSignals
    };

    return proofForContract;
}

// Example usage
async function main() {
    const inputs = {
        secret: "123456789",
        nullifierSecret: "987654321",
        merklePathIndices: Array(20).fill(0),
        merklePath: Array(20).fill(0),
        nullifier: "0",
        commitment: "0",
        amount: "1000000000000000000", // 1 ETH
        merkleRoot: "0",
        receiver: "0x1234567890123456789012345678901234567890"
    };

    try {
        const proof = await generateProof(inputs);
        console.log("Proof generated successfully:", proof);

        // Save proof to file
        fs.writeFileSync(
            "build/proof.json",
            JSON.stringify(proof, null, 2)
        );
    } catch (error) {
        console.error("Error generating proof:", error);
    }
}

if (require.main === module) {
    main().then(() => process.exit(0))
        .catch(err => {
            console.error(err);
            process.exit(1);
        });
} 