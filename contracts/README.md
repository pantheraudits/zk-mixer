# ZK Mixer Project

- **Deposit**: Users deposit ETH into the mixer with a commitment (Poseidon hash of nullifier + secret) to break the link between depositor and withdrawer.
- **Withdraw**: Users withdraw using a ZK proof (Noir, generated off-chain) that proves knowledge of a valid deposit.
- **Fixed amount**: Deposits and withdrawals are a fixed **0.001 ETH** to improve the anonymity set.

See the [main README](../README.md) for repo structure and quick start.
