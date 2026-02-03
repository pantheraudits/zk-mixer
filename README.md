# ZK Mixer

A privacy-focused Ethereum mixer that breaks the on-chain link between deposits and withdrawals using zero-knowledge proofs.

## Features

- **Deposit**: Users deposit a fixed amount of ETH (0.001 ETH) with a commitment (Poseidon hash of nullifier + secret).
- **Withdraw**: Users withdraw by submitting a ZK-SNARK proof of knowledge of a valid deposit, without revealing which one.
- **Fixed denomination**: Single amount improves the anonymity set.

## Repo structure

```
zk-mixer/
├── README.md                 # This file
├── .gitignore                # No secrets, cache, or build artifacts
├── contracts/                # Foundry project (Solidity)
│   ├── foundry.toml
│   ├── src/
│   │   └── Mixer.sol         # Main mixer contract
│   ├── script/               # Deployment scripts
│   ├── test/                 # Forge tests
│   └── lib/                  # Dependencies (e.g. forge-std)
├── circuits/                 # ZK circuits (Noir) — add when ready
│   ├── src/
│   └── Nargo.toml
└── scripts/                  # Off-chain scripts (proof gen, deploy helpers)
```

## Quick start

### Contracts (Foundry)

```bash
cd contracts
forge install   # if needed
forge build
forge test
```

### Circuits (when added)

```bash
cd circuits
nargo compile
# Generate proofs off-chain; verifier contract from bb or nargo
```

## Security

- Do not commit `.env`, private keys, or `Prover.toml`.
- `.gitignore` is set up to exclude secrets, `cache/`, `out/`, and circuit `target/`.

## Pushing to your repo

From your machine (repo root = `zk-mixer`):

```bash
cd /path/to/zk-mixer

# Initialize git (if not already)
git init

# Add everything (respects .gitignore)
git add .
git status   # confirm no .env, cache/, or secrets

git commit -m "chore: initial ZK mixer structure and Mixer contract"

# Add your remote (create the repo on GitHub/GitLab first)
git remote add origin https://github.com/YOUR_USERNAME/zk-mixer.git
# or: git remote add origin git@github.com:YOUR_USERNAME/zk-mixer.git

git branch -M main
git push -u origin main
```

To keep history clean, use meaningful commits (e.g. `feat: add withdraw nullifier check`, `docs: update README`).

## License

MIT
