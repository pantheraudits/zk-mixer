#!/usr/bin/env bash
# Generate Solidity verifier from the ZK-Mixer Noir circuit.
# Run from repo root: ./circuits/generate_verifier.sh
# Or from circuits: ./generate_verifier.sh
#
# Requires: nargo, bb (Barretenberg)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CIRCUIT_JSON="${CIRCUIT_JSON:-./target/mixer_circuit.json}"
TARGET_DIR="./target"
VERIFIER_OUT="$TARGET_DIR/Verifier.sol"
CONTRACTS_SRC="../contracts/src"

echo "[1/4] Compiling circuit..."
nargo compile

if [[ ! -f "$CIRCUIT_JSON" ]]; then
  echo "Expected circuit bytecode at $CIRCUIT_JSON (check package name in Nargo.toml)."
  exit 1
fi

echo "[2/4] Writing verification key (keccak for EVM)..."
bb write_vk --oracle_hash keccak -b "$CIRCUIT_JSON" -o "$TARGET_DIR"

echo "[3/4] Writing Solidity verifier..."
bb write_solidity_verifier -k "$TARGET_DIR/vk" -o "$VERIFIER_OUT"

echo "[4/4] Copying Verifier.sol to contracts/src..."
cp "$VERIFIER_OUT" "$CONTRACTS_SRC/Verifier.sol"

echo "Done. Verifier.sol is in $CONTRACTS_SRC"
echo "Rebuild contracts with: cd contracts && forge build"
