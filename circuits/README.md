# ZK-Mixer circuits

Noir circuit for private withdrawals: proves knowledge of a deposit (commitment in the Merkle tree) without revealing nullifier, secret, or commitment.

## Layout

- **`src/main.nr`** – Public inputs: `root`, `nullifier_hash`, `recipient`. Private inputs: `nullifier`, `secret`, `merkle_proof[20]`, `is_even[20]`. Computes commitment = Poseidon(nullifier, secret), checks nullifier hash, verifies Merkle path, binds recipient.
- **`src/merkle_tree.nr`** – `compute_merkle_root(leaf, proof, is_even)` for depth-20 tree using Poseidon.

## Dependencies

- **poseidon** – Local copy in `lib/poseidon` (poseidon2 only). If `nargo compile` fails inside the poseidon crate (e.g. “Indexing arrays must be done with u32, not Field”), try another tag or update Noir.

---

## Generating the Solidity verifier (Nargo + Barretenberg)

Use this workflow to produce `Verifier.sol` for the Mixer contract.

### Prerequisites

- **Nargo** – Noir compiler (`nargo compile`).
- **Barretenberg (bb)** – Backend for verification key and Solidity verifier generation. Install from [Aztec's barretenberg](https://github.com/AztecProtocol/barretenberg) or your Noir toolchain.

### Step 1: Compile the circuit

From the **circuits** directory:

```bash
cd circuits
nargo compile
```

Optional: clean and recompile to avoid stale artifacts:

```bash
rm -rf target/
nargo compile
```

This creates `target/mixer_circuit.json` (ACIR bytecode). Fix any compiler warnings (e.g. unused variables) before proceeding.

### Step 2: Generate the verification key (VK)

Use **keccak** for EVM compatibility:

```bash
bb write_vk --oracle_hash keccak -b ./target/mixer_circuit.json -o ./target
```

This writes `target/vk`. The `-b` path must point to the compiled circuit JSON (name matches your package in `Nargo.toml`).

### Step 3: Generate the verifier contract

```bash
bb write_solidity_verifier -k ./target/vk -o ./target/Verifier.sol
```

This creates `target/Verifier.sol`.

### Step 4: Move verifier into contracts

```bash
mv ./target/Verifier.sol ../contracts/src/
```

(Or copy if you want to keep a copy under `target/`.)

### Step 5: Use in Mixer

`Mixer.sol` already imports and uses the verifier. Ensure:

- The verifier’s **public input count and order** match the circuit: `root`, `nullifier_hash`, `recipient`, and (if your verifier expects it) `denomination` in the same order as in `withdraw` when calling `verifyProof(_proof, publicInputs)`.

---

## One-liner / script

From the **circuits** directory you can run:

```bash
nargo compile && \
bb write_vk --oracle_hash keccak -b ./target/mixer_circuit.json -o ./target && \
bb write_solidity_verifier -k ./target/vk -o ./target/Verifier.sol && \
mv ./target/Verifier.sol ../contracts/src/
```

Or use the provided script (see below).

---

## Public inputs order

For the Mixer’s `withdraw` and the generated verifier, public inputs must match the circuit and be in this order:

1. `root` (bytes32)
2. `nullifier_hash` (bytes32)
3. `recipient` (address → uint256/Field)
4. `denomination` (uint256) – set by the Mixer when calling the verifier

The generated `Verifier.sol` will define the expected number of public inputs (e.g. `NUMBER_OF_PUBLIC_INPUTS`). Adjust `Mixer.sol`’s `publicInputs` array. The generated contract may expose verify(bytes memory proof, bytes32[] memory publicInputs). Ensure IVerifier in Mixer.sol and the encoding of public inputs match; update the interface or withdraw logic (e.g. `verify(proof, publicInputs)` vs `verifyProof(...)`).
