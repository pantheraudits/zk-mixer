// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVerifier {
    function verifyProof(
        bytes calldata proof,
        uint256[] calldata publicInputs
    ) external view returns (bool);
}

contract Mixer {
    IVerifier public immutable i_verifier;

    mapping(bytes32 => bool) public s_commitments;
    mapping(bytes32 => bool) public s_usedNullifiers;

    uint256 public constant DENOMINATION = 0.001 ether;

    error Mixer__CommitmentAlreadyAdded(bytes32 commitment);
    error Mixer__DepositAmountNotCorrect(uint256 amountSent, uint256 expectedAmount);
    error Mixer__InvalidZKProof();
    error Mixer__NullifierAlreadyUsed(bytes32 nullifierHash);

    constructor(address _verifierAddress) {
        i_verifier = IVerifier(_verifierAddress);
    }

    /// @notice Deposit funds into the mixer
    /// @param _commitment The Poseidon hash of the user's (off-chain generated) nullifier and secret.
    function deposit(bytes32 _commitment) external payable {
        if (s_commitments[_commitment]) {
            revert Mixer__CommitmentAlreadyAdded(_commitment);
        }
        if (msg.value != DENOMINATION) {
            revert Mixer__DepositAmountNotCorrect(msg.value, DENOMINATION);
        }
        s_commitments[_commitment] = true;
        // TODO: Add _commitment to the on-chain Incremental Merkle Tree
        // emit DepositEvent(_commitment, msg.sender, block.timestamp);
    }

    /// @notice Withdraw funds from the mixer in a private way
    /// @param _proof The ZK-SNARK proof.
    /// @param _merkleRoot The Merkle root against which the proof was generated (public input to ZK proof).
    /// @param _nullifierHash A hash unique to the deposit, revealed to prevent double-spending (public input to ZK proof).
    /// @param _recipient The address to send the withdrawn funds to (public input to ZK proof).
    function withdraw(
        bytes memory _proof,
        bytes32 _merkleRoot,
        bytes32 _nullifierHash,
        address payable _recipient
    ) external {
        // TODO: Merkle root check when Incremental Merkle Tree is integrated
        // require(_merkleRoot == currentMerkleRootInContract, "Stale Merkle root");

        if (s_usedNullifiers[_nullifierHash]) {
            revert Mixer__NullifierAlreadyUsed(_nullifierHash);
        }

        uint256[] memory publicInputs = new uint256[](4);
        publicInputs[0] = uint256(_merkleRoot);
        publicInputs[1] = uint256(_nullifierHash);
        publicInputs[2] = uint256(uint160(_recipient));
        publicInputs[3] = DENOMINATION;

        bool isValid = i_verifier.verifyProof(_proof, publicInputs);
        if (!isValid) {
            revert Mixer__InvalidZKProof();
        }

        s_usedNullifiers[_nullifierHash] = true;

        (bool success, ) = _recipient.call{value: DENOMINATION}("");
        if (!success) {
            revert("Mixer: transfer failed");
        }
        // emit WithdrawalEvent(_recipient, _nullifierHash, block.timestamp);
    }

    receive() external payable {
        revert("Mixer: use deposit()");
    }
}
