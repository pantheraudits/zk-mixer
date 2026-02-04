// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

/// @title Incremental Merkle Tree for on-chain commitment storage (Poseidon-based)
/// @notice Fixed-depth tree with pre-computed zero subtree hashes; supports O(depth) insertions
contract IncrementalMerkleTree {
    uint32 public immutable i_depth;

    /// @notice Pre-computed roots of zero subtrees (zeros[0] = empty leaf, zeros[k] = Poseidon(zeros[k-1], zeros[k-1]))
    mapping(uint256 => bytes32) internal _zeros;

    /// @notice Historical Merkle roots (circular buffer) to allow withdrawals with slightly stale proofs
    mapping(uint256 => bytes32) public s_roots;
    uint32 public constant ROOT_HISTORY_SIZE = 30;
    /// @notice Index in s_roots where the most recent root is stored
    uint32 public s_currentRootIndex;

    /// @notice Index of the next leaf to be inserted (0 to 2^depth - 1)
    uint32 public s_nextLeafIndex;

    /// @notice Cached left-sibling hashes per level (level => hash), used when processing odd-indexed nodes
    mapping(uint32 => bytes32) public s_cachedSubtrees;

    /// @dev BN254 scalar field modulus (Poseidon operates over this field)
    uint256 internal constant PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @dev Empty leaf: keccak256("cyfrin") % PRIME (lesson value)
    bytes32 public constant ZEROS_0 = bytes32(0x0d823319708ab99ec915efd4f7e03d11ca1790918e8f04cd14100aceca2aa9ff);

    error IncrementalMerkleTree_DepthShouldBeGreaterThanZero();
    error IncrementalMerkleTree_DepthShouldBeLessThan32();
    error IncrementalMerkleTree__MerkleTreeFull(uint256 nextLeafIndex);
    error IncrementalMerkleTree_LevelOutOfBounds(uint256 level);

    constructor(uint32 _depth) {
        if (_depth == 0) {
            revert IncrementalMerkleTree_DepthShouldBeGreaterThanZero();
        }
        if (_depth >= 32) {
            revert IncrementalMerkleTree_DepthShouldBeLessThan32();
        }

        i_depth = _depth;

        // Initialize zero subtree hashes: zeros[0] = empty leaf, zeros[i] = Poseidon(zeros[i-1], zeros[i-1])
        _zeros[0] = ZEROS_0;
        for (uint32 i = 1; i <= _depth; i++) {
            _zeros[i] = _poseidonHash(_zeros[i - 1], _zeros[i - 1]);
        }

        s_roots[0] = _zeros[_depth];
        s_currentRootIndex = 0;
        s_nextLeafIndex = 0;
    }

    /// @notice Returns the pre-computed hash of a zero-filled subtree of height i
    /// @param i Level (0 = single empty leaf, 1 = subtree of 2 leaves, etc.)
    function zeros(uint32 i) public view returns (bytes32) {
        if (i > i_depth) {
            revert IncrementalMerkleTree_LevelOutOfBounds(i);
        }
        return _zeros[i];
    }

    /// @notice Hash two nodes with Poseidon (left-then-right order)
    function _poseidonHash(bytes32 _left, bytes32 _right) internal pure returns (bytes32) {
        uint256 leftField = uint256(_left) % PRIME;
        uint256 rightField = uint256(_right) % PRIME;
        uint256[2] memory input;
        input[0] = leftField;
        input[1] = rightField;
        return bytes32(PoseidonT3.hash(input));
    }

    /// @notice Insert a new leaf at the next available index; updates s_root and caches left siblings.
    /// @param _leaf The leaf value (e.g. commitment hash) to insert.
    /// @return The index at which the leaf was inserted (for Deposit event / off-chain tree reconstruction).
    function _insert(bytes32 _leaf) internal returns (uint32) {
        uint32 _insertedLeafIndex = s_nextLeafIndex;

        if (_insertedLeafIndex == uint32(2 ** i_depth)) {
            revert IncrementalMerkleTree__MerkleTreeFull(_insertedLeafIndex);
        }

        uint32 currentIndex = _insertedLeafIndex;
        bytes32 currentHash = _leaf;
        bytes32 left;
        bytes32 right;

        for (uint32 i = 0; i < i_depth; i++) {
            if (currentIndex % 2 == 0) {
                left = currentHash;
                right = zeros(i);
                s_cachedSubtrees[i] = currentHash;
                currentHash = _poseidonHash(left, right);
            } else {
                left = s_cachedSubtrees[i];
                right = currentHash;
                currentHash = _poseidonHash(left, right);
            }
            currentIndex = currentIndex / 2;
        }

        uint32 newRootIndex = (s_currentRootIndex + 1) % ROOT_HISTORY_SIZE;
        s_currentRootIndex = newRootIndex;
        s_roots[newRootIndex] = currentHash;
        s_nextLeafIndex = _insertedLeafIndex + 1;

        return _insertedLeafIndex;
    }

    /// @notice Returns the current (most recent) Merkle root
    function getRoot() public view returns (bytes32) {
        return s_roots[s_currentRootIndex];
    }

    /// @notice Returns true if _root is in the stored history of roots (mitigates stale proof reverts)
    function isKnownRoot(bytes32 _root) public view returns (bool) {
        if (_root == bytes32(0)) {
            return false;
        }

        uint32 _currentRootIndex = s_currentRootIndex;
        uint32 i = _currentRootIndex;

        do {
            if (s_roots[i] == _root) {
                return true;
            }
            if (i == 0) {
                i = ROOT_HISTORY_SIZE;
            }
            i--;
        } while (i != _currentRootIndex);

        return false;
    }
}
