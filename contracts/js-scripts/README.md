# ZK-Mixer JS/TS scripts

Used by Foundry tests via FFI to generate commitments and ZK proofs off-chain.

## Scripts

- **generateCommitment.ts** – Generates `(commitment, nullifier, secret)` with Barretenberg Poseidon2; stdout is ABI-encoded `(bytes32, bytes32, bytes32)`.
- **generateProof.ts** – Generates a withdrawal ZK proof: parses CLI args (nullifier, secret, recipient, leaves), builds Merkle tree, gets proof data, runs Noir circuit with UltraHonk backend, stdout is ABI-encoded `bytes` (the proof).

## Prerequisites for generateProof.ts

1. **Compiled Noir circuit**  
   From the repo root:
   ```bash
   cd circuits && nargo compile
   ```
   This creates `circuits/target/mixer_circuit.json`. The script looks for `mixer_circuit.json`, `circuits.json`, or `main.json` in `circuits/target/`.

2. **Dependencies**  
   From `contracts/js-scripts`:
   ```bash
   npm install
   ```

## ZERO_VALUES / Merkle tree

`merkleTree.ts` uses the same empty-leaf hash as the on-chain Mixer (`ZEROS_0`) and the same Poseidon-based zero subtree hashes. Any change to `IncrementalMerkleTree.sol` or the Noir `merkle_tree.nr` zeros must be reflected here or proofs will not verify on-chain.

## Running tests

From `contracts/`:

```bash
forge test --match-contract MixerTest -vv
```

Use `--offline` if you hit Foundry proxy/network issues. With a **mock verifier**, withdrawal tests pass using a stub proof. With a **real verifier** and compiled circuit, run `nargo compile` in `circuits/` first; then `generateProof.ts` will produce a valid proof and the test can use it (and the script must output `nullifierHash` if the test is to pass it to `withdraw`).
