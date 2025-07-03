const fs = require('fs');
const snarkjs = require('snarkjs');

async function parseProof() {
    // Read proof and public inputs
    const proof = JSON.parse(fs.readFileSync('circuits/build/proof.json'));
    const publicSignals = JSON.parse(fs.readFileSync('circuits/build/public.json'));

    // Format for Solidity
    const solProof = {
        _pA: proof.pi_a.slice(0, 2),
        _pB: [
            [proof.pi_b[0][1], proof.pi_b[0][0]],
            [proof.pi_b[1][1], proof.pi_b[1][0]]
        ],
        _pC: proof.pi_c.slice(0, 2),
        _pubSignals: publicSignals
    };

    // Write formatted proof
    fs.writeFileSync(
        'circuits/build/solidity_proof.json',
        JSON.stringify(solProof, null, 2)
    );

    console.log('Proof parsed and saved to solidity_proof.json');
    console.log('Solidity-compatible format:');
    console.log(JSON.stringify(solProof, null, 2));
}

parseProof().catch(console.error); 