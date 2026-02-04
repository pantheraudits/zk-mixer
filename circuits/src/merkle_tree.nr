// Merkle root computation from leaf, sibling path, and position flags.
// Uses Poseidon for hashing (must match on-chain tree and commitment hash).
use dep::poseidon;

/// Compute the Merkle root from a leaf, proof path, and is_even path indicators.
/// For a depth-20 tree we perform 20 hashing steps.
/// is_even[i] = true  => current_hash is left input, proof[i] is right.
/// is_even[i] = false => proof[i] is left input, current_hash is right.
pub fn compute_merkle_root(leaf: Field, proof: [Field; 20], is_even: [bool; 20]) -> Field {
    let mut current_hash: Field = leaf;

    for i in 0..20 {
        let (left_input, right_input): (Field, Field) = if is_even[i] {
            (current_hash, proof[i])
        } else {
            (proof[i], current_hash)
        };

        current_hash = poseidon::poseidon2::Poseidon2::hash([left_input, right_input], 2);
    }

    current_hash
}
