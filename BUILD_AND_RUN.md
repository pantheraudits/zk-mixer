# ZK-Mixer: Build and run (step-by-step)

All commands assume you are in the path shown. Run from the **repo root** (`zk-mixer`) unless stated otherwise.

---

## Prerequisites

- **Node.js** (v18+) and **npm** – for proof/commitment scripts used by tests
- **Noir (nargo)** – [Install Noir](https://noir-lang.org/docs/getting_started/installation/)
- **Barretenberg (bb)** – [Aztec barretenberg](https://github.com/AztecProtocol/barretenberg) (same toolchain as Noir often includes it)
- **Foundry** – [Install Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`)

---

## 1. Clone and enter repo (if needed)

```bash
cd /path/to/zk-mixer
```

---

## 2. Install contract dependencies (Foundry)

```bash
cd contracts
forge install
cd ..
```

If you already ran this once, you can skip it. Fix any missing submodules if `forge build` later complains.

---

## 3. Compile the Noir circuit

From the **circuits** directory:

```bash
cd circuits
nargo compile
cd ..
```

- This produces `circuits/target/mixer_circuit.json` (ACIR / compiled circuit).
- To force a clean build: `rm -rf circuits/target` then run `nargo compile` again from `circuits`.

---

## 4. Generate the Solidity verifier (VK + Verifier.sol)

Still from **circuits** (or repo root and then `cd circuits`):

```bash
cd circuits
bb write_vk --oracle_hash keccak -b ./target/mixer_circuit.json -o ./target
bb write_solidity_verifier -k ./target/vk -o ./target/Verifier.sol
cp ./target/Verifier.sol ../contracts/src/
cd ..
```

Or use the script (from repo root or from `circuits`):

```bash
./circuits/generate_verifier.sh
```

- This creates `contracts/src/Verifier.sol`.
- If the generated contract uses a different interface (e.g. `verify` instead of `verifyProof`), either:
  - Change `Mixer.sol` to use that function name, or
  - Add a thin wrapper contract that implements `IVerifier.verifyProof` and calls the generated verifier.

---

## 5. Install JS dependencies (for tests that generate proofs)

From **repo root**:

```bash
cd contracts/js-scripts
npm install
cd ../..
```

---

## 6. Build the Solidity contracts

From **repo root**:

```bash
cd contracts
forge build
cd ..
```

You should see `Compiler run successful!`.

---

## 7. Run tests

From **contracts**:

```bash
cd contracts
forge test
```

- With **MockVerifier** (default in tests): deposit and withdrawal tests pass; `testAnotherAddressSendProof` is skipped.
- To run **with the real Verifier**: deploy the generated `Verifier.sol`, pass its address into the test’s `Mixer` constructor (replace `MockVerifier` in the test setup with the real verifier address), and re-run tests; `testAnotherAddressSendProof` should then run and pass.

To run a single test with verbose output:

```bash
forge test --mt testMakeDeposit -vv
forge test --mt testMakeWithdrawal -vv
forge test --mt testAnotherAddressSendProof -vv
```

---

## 8. (Optional) Run only contract tests without FFI

If you want to run tests that do **not** call the JS proof scripts (no FFI), you can run tests that don’t use `vm.ffi`. The main deposit/withdrawal tests use FFI, so they need `npx tsx` and the JS deps installed. To enable FFI in Foundry (required for those tests), ensure `foundry.toml` has:

```toml
[profile.default]
ffi = true
```

---

## Quick reference (copy-paste)

From a clean clone, from **repo root**:

```bash
# Dependencies
cd contracts && forge install && cd ..
cd contracts/js-scripts && npm install && cd ../..

# Circuit + verifier
cd circuits
nargo compile
bb write_vk --oracle_hash keccak -b ./target/mixer_circuit.json -o ./target
bb write_solidity_verifier -k ./target/vk -o ./target/Verifier.sol
cp ./target/Verifier.sol ../contracts/src/
cd ..

# Build and test
cd contracts
forge build
forge test
cd ..
```

---

## Troubleshooting

| Issue | What to do |
|--------|------------|
| `nargo compile` fails (e.g. in poseidon) | Update Noir or try a different `poseidon` tag in `circuits/Nargo.toml`. |
| `bb: command not found` | Install Barretenberg and ensure `bb` is on your `PATH`. |
| `forge install` fails / submodule errors | Run from `contracts`: `git submodule update --init --recursive`; fix any permission or SSH keys for private repos. |
| Tests fail with FFI / script errors | Ensure `contracts/js-scripts/node_modules` exists (`npm install` in `contracts/js-scripts`) and `ffi = true` in `foundry.toml`. |
| Verifier function name mismatch | Open `contracts/src/Verifier.sol` and align its external `verify` (or similar) with `IVerifier.verifyProof` in `Mixer.sol`, or add a wrapper. |
