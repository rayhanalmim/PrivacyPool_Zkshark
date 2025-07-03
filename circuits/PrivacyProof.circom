pragma circom 2.1.4;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template PrivacyProof() {
    // Private inputs
    signal input secret;
    signal input nullifierSecret;
    signal input merklePathIndices[20];
    signal input merklePath[20];

    // Public inputs
    signal input nullifier;
    signal input commitment;
    signal input amount;
    signal input merkleRoot;
    signal input receiver;

    // Verify commitment = hash(receiver, secret)
    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== receiver;
    commitmentHasher.inputs[1] <== secret;
    commitment === commitmentHasher.out;

    // Verify nullifier = hash(commitment, secret, nullifierSecret)
    component nullifierHasher = Poseidon(3);
    nullifierHasher.inputs[0] <== commitment;
    nullifierHasher.inputs[1] <== secret;
    nullifierHasher.inputs[2] <== nullifierSecret;
    nullifier === nullifierHasher.out;

    // Verify merkle path
    signal merklePathRoot;
    component merkleHashers[20];
    
    for (var i = 0; i < 20; i++) {
        merkleHashers[i] = Poseidon(2);
        
        // If pathIndex is 0, current is left, sibling is right
        // If pathIndex is 1, current is right, sibling is left
        signal left;
        signal right;
        
        left = merklePathIndices[i] * merklePath[i] + (1 - merklePathIndices[i]) * (i == 0 ? commitment : merkleHashers[i-1].out);
        right = merklePathIndices[i] * (i == 0 ? commitment : merkleHashers[i-1].out) + (1 - merklePathIndices[i]) * merklePath[i];
        
        merkleHashers[i].inputs[0] <== left;
        merkleHashers[i].inputs[1] <== right;
    }
    
    merkleRoot === merkleHashers[19].out;
} 