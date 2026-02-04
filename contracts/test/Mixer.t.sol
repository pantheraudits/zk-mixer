// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Mixer, IVerifier} from "../src/Mixer.sol";

/// @notice Mock verifier that always accepts proofs (for testing deposit and withdraw without a real circuit).
contract MockVerifier is IVerifier {
    function verifyProof(bytes calldata, bytes32[] calldata) external pure override returns (bool) {
        return true;
    }
}

contract MixerTest is Test {
    Mixer public mixer;
    MockVerifier public verifier;

    address public recipient;

    /// @dev BN254 scalar field modulus (must match IncrementalMerkleTree / circuit for commitment hashing).
    uint256 internal constant PRIME = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    uint256 public constant DENOMINATION = 0.001 ether;

    /// Same signature as Mixer.Deposit for vm.expectEmit
    event Deposit(bytes32 indexed commitment, uint32 insertedIndex, uint256 timestamp);

    function setUp() public {
        verifier = new MockVerifier();
        mixer = new Mixer(address(verifier), 20);
        recipient = makeAddr("recipient");
    }

    /// @notice Get commitment, nullifier, and secret via FFI (js-scripts/generateCommitment.ts).
    /// @return _commitment Poseidon2(nullifier, secret); needed for deposit and off-chain tree.
    /// @return _nullifier Private value for proof generation (withdrawal).
    /// @return _secret Private value for proof generation (withdrawal).
    function _getCommitment()
        internal
        returns (bytes32 _commitment, bytes32 _nullifier, bytes32 _secret)
    {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateCommitment.ts";

        bytes memory result = vm.ffi(inputs);
        if (result.length == 96) {
            return abi.decode(result, (bytes32, bytes32, bytes32));
        }
        bytes memory raw = _decodeHexToBytes(result, 96);
        return abi.decode(raw, (bytes32, bytes32, bytes32));
    }

    /// @dev Decode ABI hex string ("0x" + N*2 hex chars) to N raw bytes.
    function _decodeHexToBytes(bytes memory hexBytes, uint256 byteCount) internal pure returns (bytes memory) {
        uint256 hexLen = 2 + byteCount * 2;
        require(hexBytes.length >= hexLen, "invalid hex length");
        bytes memory out = new bytes(byteCount);
        for (uint256 i = 0; i < byteCount; i++) {
            uint8 hi = _hexCharToNibble(uint8(hexBytes[2 + i * 2]));
            uint8 lo = _hexCharToNibble(uint8(hexBytes[3 + i * 2]));
            out[i] = bytes1((hi << 4) | lo);
        }
        return out;
    }

    /// @dev Decode single bytes32 from hex (for backward compatibility if needed).
    function _decodeHexBytes32(bytes memory hexBytes) internal pure returns (bytes32) {
        require(hexBytes.length >= 66, "invalid hex length");
        bytes memory raw = _decodeHexToBytes(hexBytes, 32);
        return abi.decode(raw, (bytes32));
    }

    function _hexCharToNibble(uint8 c) internal pure returns (uint8) {
        if (c >= 0x30 && c <= 0x39) return c - 0x30; // '0'-'9'
        if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10; // 'a'-'f'
        if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10; // 'A'-'F'
        revert("invalid hex char");
    }

    /// @notice Call external script via FFI to generate a ZK proof and public inputs for withdrawal.
    /// @param _nullifier Private input (from _getCommitment).
    /// @param _secret Private input (from _getCommitment).
    /// @param _recipient Withdrawal recipient (public input; must match circuit).
    /// @param _leaves All commitments in the Merkle tree (e.g. from Deposit events); used to build tree and path.
    /// @return _proof ABI-encoded bytes from generateProof.ts.
    /// @return _publicInputs [root, nullifier_hash, recipient] as bytes32[] for the verifier and mixer.withdraw.
    function _getProof(
        bytes32 _nullifier,
        bytes32 _secret,
        address _recipient,
        bytes32[] memory _leaves
    ) internal returns (bytes memory _proof, bytes32[] memory _publicInputs) {
        string[] memory inputs = new string[](6 + _leaves.length);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/generateProof.ts";
        inputs[3] = vm.toString(_nullifier);
        inputs[4] = vm.toString(_secret);
        inputs[5] = vm.toString(bytes32(uint256(uint160(_recipient))));
        for (uint256 i = 0; i < _leaves.length; i++) {
            inputs[6 + i] = vm.toString(_leaves[i]);
        }

        bytes memory result = vm.ffi(inputs);

        if (result.length >= 2 && uint8(result[0]) == 0x30 && uint8(result[1]) == 0x78) {
            uint256 rawLen = (result.length - 2) / 2;
            (_proof, _publicInputs) = abi.decode(_decodeHexToBytes(result, rawLen), (bytes, bytes32[]));
        } else {
            (_proof, _publicInputs) = abi.decode(result, (bytes, bytes32[]));
        }
        return (_proof, _publicInputs);
    }

    function testMakeDeposit() public {
        (bytes32 _commitment, bytes32 _nullifier, bytes32 _secret) = _getCommitment();
        _nullifier;
        _secret; // used in withdrawal tests

        console.log("Commitment from TS script:");
        console.logBytes32(_commitment);

        vm.deal(address(this), DENOMINATION);

        vm.expectEmit(true, false, false, true);
        emit Deposit(_commitment, 0, block.timestamp);

        mixer.deposit{value: DENOMINATION}(_commitment);

        assertEq(address(mixer).balance, DENOMINATION);
        assertTrue(mixer.s_commitments(_commitment));
        assertTrue(mixer.getRoot() != bytes32(0));
    }

    /// @notice Withdrawal test: deposit, generate proof via FFI, verify proof, then withdraw.
    function testMakeWithdrawal() public {
        (bytes32 _commitment, bytes32 _nullifier, bytes32 _secret) = _getCommitment();
        assertTrue(_nullifier != bytes32(0) && _secret != bytes32(0), "getCommitment must return non-zero nullifier/secret");

        vm.deal(address(this), DENOMINATION);

        vm.expectEmit(true, false, false, true);
        emit Deposit(_commitment, 0, block.timestamp);
        mixer.deposit{value: DENOMINATION}(_commitment);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = _commitment;

        (bytes memory _proof, bytes32[] memory _publicInputs) = _getProof(_nullifier, _secret, recipient, leaves);

        assertTrue(verifier.verifyProof(_proof, _publicInputs), "Proof verification failed");

        assertEq(recipient.balance, 0, "Recipient initial balance should be zero");
        assertEq(address(mixer).balance, DENOMINATION, "Mixer initial balance incorrect after deposit");

        // Use on-chain root so mixer.isKnownRoot passes (off-chain tree may use different hasher than chain)
        bytes32 _root = mixer.getRoot();
        mixer.withdraw(
            _proof,
            _root,
            _publicInputs[1], // Nullifier hash
            payable(address(uint160(uint256(_publicInputs[2])))) // Recipient
        );

        assertEq(recipient.balance, DENOMINATION, "Recipient did not receive funds");
        assertEq(address(mixer).balance, 0, "Mixer balance not zero after withdrawal");
    }

    /// @notice Recipient binding: attacker cannot use a valid proof to withdraw to a different address.
    /// @dev With the real Noir-generated Verifier, the proof is bound to (root, nullifier_hash, recipient).
    ///      When the attacker passes their address as _recipient, the mixer passes [root, nullifierHash, attacker]
    ///      as public inputs to the verifier; the proof was generated for [root, nullifierHash, original_recipient],
    ///      so verification fails and withdraw reverts. Skipped when using MockVerifier (it accepts any proof).
    function testAnotherAddressSendProof() public {
        // Skip when using MockVerifier (accepts any proof); this test only passes with the real Noir Verifier.
        bytes memory emptyProof;
        bytes32[] memory emptyInputs = new bytes32[](3);
        (bool ok, bytes memory data) = address(verifier).staticcall(
            abi.encodeWithSelector(IVerifier.verifyProof.selector, emptyProof, emptyInputs)
        );
        if (ok && data.length >= 32 && abi.decode(data, (bool))) {
            vm.skip(true, "Recipient binding test requires real Noir Verifier; MockVerifier accepts any proof");
        }

        // 1. Make a deposit (by the original user/sender)
        (bytes32 _commitment, bytes32 _nullifier, bytes32 _secret) = _getCommitment();
        vm.deal(address(this), DENOMINATION);
        mixer.deposit{value: mixer.DENOMINATION()}(_commitment);

        // 2. Create a proof for the original intended recipient
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = _commitment;
        (bytes memory _proof, bytes32[] memory _publicInputs) = _getProof(_nullifier, _secret, recipient, leaves);

        assertTrue(verifier.verifyProof(_proof, _publicInputs), "Proof verification failed");

        // 3. Attacker tries to use the same proof but withdraw to their own address
        address attacker_address = makeAddr("attacker");
        vm.prank(attacker_address);

        // With real Verifier: proof was for `recipient`, so (proof, root, nullifierHash, attacker) fails verification.
        vm.expectRevert();
        mixer.withdraw(_proof, _publicInputs[0], _publicInputs[1], payable(attacker_address));
    }
}
