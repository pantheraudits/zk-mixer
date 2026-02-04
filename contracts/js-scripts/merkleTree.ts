/**
 * Off-chain Merkle tree for the ZK-Mixer. Uses Poseidon2 (Barretenberg) and
 * ZERO_VALUES that MUST match IncrementalMerkleTree.sol and the Noir merkle_tree.nr.
 */
import type { Barretenberg } from "@aztec/bb.js";
import { Fr } from "@aztec/bb.js";

const DEPTH = 20;
const MAX_LEAVES = 2 ** DEPTH;

/** Empty leaf hash — must match Mixer ZEROS_0: keccak256("cyfrin") % PRIME */
const ZEROS_0_HEX = "0x0d823319708ab99ec915efd4f7e03d11ca1790918e8f04cd14100aceca2aa9ff";

function normalizeHex(hex: string): string {
    const h = hex.startsWith("0x") ? hex.slice(2) : hex;
    return "0x" + h.replace(/^0+/, "") || "0x0";
}

export interface MerkleProofData {
    root: Fr;
    pathElements: Fr[];
    pathIndices: number[];
    leaf: Fr;
}

export interface MerkleTreeInstance {
    root: Fr;
    proof(commitmentOrLeafHex: string): MerkleProofData;
}

/**
 * Build Merkle tree from leaves and return instance with root and proof(commitment).
 * ZERO_VALUES are computed to match on-chain IncrementalMerkleTree (Poseidon(zeros[i-1], zeros[i-1])).
 */
export async function merkleTree(
    leaves: string[],
    bb: Barretenberg
): Promise<MerkleTreeInstance> {
    const zeros: Fr[] = [];
    zeros[0] = Fr.fromString(ZEROS_0_HEX);
    for (let i = 1; i <= DEPTH; i++) {
        zeros[i] = await bb.poseidon2Hash([zeros[i - 1], zeros[i - 1]]);
    }

    const paddedLeaves: Fr[] = [];
    for (let i = 0; i < MAX_LEAVES; i++) {
        if (i < leaves.length) {
            const leaf = leaves[i].startsWith("0x")
                ? Fr.fromString(leaves[i])
                : Fr.fromString("0x" + leaves[i]);
            paddedLeaves.push(leaf);
        } else {
            paddedLeaves.push(zeros[0]);
        }
    }

    const layers: Fr[][] = [paddedLeaves];
    for (let level = 0; level < DEPTH; level++) {
        const current = layers[level];
        const next: Fr[] = [];
        for (let i = 0; i < current.length; i += 2) {
            const left = current[i];
            const right = current[i + 1];
            const h = await bb.poseidon2Hash([left, right]);
            next.push(h);
        }
        layers.push(next);
    }

    const root = layers[DEPTH][0];

    function proof(commitmentOrLeafHex: string): MerkleProofData {
        const needle = commitmentOrLeafHex.startsWith("0x")
            ? commitmentOrLeafHex
            : "0x" + commitmentOrLeafHex;
        const leafFr = Fr.fromString(needle);
        const needleNorm = normalizeHex(needle);
        let leafIndex = -1;
        for (let i = 0; i < paddedLeaves.length; i++) {
            const leafStr = paddedLeaves[i].toString();
            if (leafStr === leafFr.toString() || normalizeHex(leafStr) === needleNorm) {
                leafIndex = i;
                break;
            }
        }
        if (leafIndex < 0) {
            throw new Error("Commitment not found in tree");
        }

        const pathElements: Fr[] = [];
        const pathIndices: number[] = [];
        let index = leafIndex;
        for (let level = 0; level < DEPTH; level++) {
            const siblingIndex = index ^ 1;
            pathElements.push(layers[level][siblingIndex]);
            pathIndices.push(index % 2);
            index = index >> 1;
        }

        return {
            root,
            pathElements,
            pathIndices,
            leaf: leafFr,
        };
    }

    return { root, proof };
}
