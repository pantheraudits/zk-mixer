import { Barretenberg, Fr } from "@aztec/bb.js";
import { ethers } from "ethers";

/**
 * Generates commitment = Poseidon2(nullifier, secret) plus nullifier and secret for withdrawal tests.
 * Outputs ABI-encoded (commitment, nullifier, secret) as hex to stdout for Foundry FFI.
 */
export default async function generateCommitment(): Promise<string> {
    const bb = await Barretenberg.new();

    const nullifier: Fr = Fr.random();
    const secret: Fr = Fr.random();

    const commitment: Fr = await bb.poseidon2Hash([nullifier, secret]);

    const abiCoder = ethers.AbiCoder.defaultAbiCoder();
    const commitmentBuf = Buffer.from(commitment.toBuffer());
    const nullifierBuf = Buffer.from(nullifier.toBuffer());
    const secretBuf = Buffer.from(secret.toBuffer());

    const encodedHex = abiCoder.encode(
        ["bytes32", "bytes32", "bytes32"],
        [commitmentBuf, nullifierBuf, secretBuf]
    );

    // Foundry FFI expects valid UTF-8; output hex so Solidity can decode.
    return encodedHex;
}

(async () => {
    generateCommitment()
        .then((result) => {
            process.stdout.write(result);
            process.exit(0);
        })
        .catch((error) => {
            console.error("Error generating commitment:", error);
            process.exit(1);
        });
})();
