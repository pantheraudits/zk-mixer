// ZK-Mixer withdrawal circuit: proves knowledge of a deposit (commitment in tree)
// without revealing nullifier, secret, or commitment. Public inputs: root, nullifier_hash, recipient.
mod merkle_tree;

use dep::poseidon;

fn main(
    // Public inputs
    root: pub Field,
    nullifier_hash: pub Field,
    recipient: pub Field,
    // Private inputs
    nullifier: Field,
    secret: Field,
    merkle_proof: [Field; 20],
    is_even: [bool; 20],
) {
    // 1. Recompute commitment = Poseidon(nullifier, secret) (same as deposit)
    let commitment: Field = poseidon::poseidon2::Poseidon2::hash([nullifier, secret], 2);

    // 2. Verify nullifier hashes to the public nullifier_hash (prevents double-spend forgery)
    let computed_nullifier_hash: Field = poseidon::poseidon2::Poseidon2::hash([nullifier], 1);
    assert(computed_nullifier_hash == nullifier_hash);

    // 3. Verify commitment is in the Merkle tree with the given root
    let computed_root: Field = merkle_tree::compute_merkle_root(commitment, merkle_proof, is_even);
    assert(computed_root == root);

    // 4. Recipient binding: pub Field ensures recipient is part of the proof's public statement.
    //    No dummy calculation (e.g. recipient * recipient) is needed; Noir/bb bind all pub inputs to the proof.
    //    The on-chain verifier checks (root, nullifier_hash, recipient); only this recipient can receive funds.
    assert(recipient != 0); // Optional: reject zero address; binding is guaranteed by pub alone.
}
