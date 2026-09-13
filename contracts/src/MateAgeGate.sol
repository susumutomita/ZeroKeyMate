// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface IAgeGroth16Verifier {
    function verifyProof(bytes calldata proof, uint256[8] calldata inputs) external view;
}

/// Testnet-only, direct proof verification. The merchant calls this with eth_call:
/// no attestor, card upload, signer, gas payment or stored identity is involved.
/// It proves the narrow physical JPKI signing-certificate profile and age >= 20.
/// Certificate revocation is NOT checked. This is not a completed eKYC service.
contract MateAgeGate {
    address public immutable verifier;
    bytes32 public immutable verifierCodeHash;
    uint256 public constant MINIMUM_AGE = 20;
    uint256 public constant ORDER_DURATION = 900;

    error UnsupportedChain();
    error InvalidVerifier();

    constructor(address verifier_, bytes32 expectedCodeHash) {
        if (block.chainid != 5042002 && block.chainid != 31337) revert UnsupportedChain();
        if (verifier_.code.length == 0 || expectedCodeHash == bytes32(0)
            || verifier_.codehash != expectedCodeHash) revert InvalidVerifier();
        verifier = verifier_;
        verifierCodeHash = expectedCodeHash;
    }

    /// The caller supplies its own recomputed order commitment, not a hash chosen
    /// by the prover. The Worker binds that hash to chain, this gate, payer, item,
    /// quantity, token, recipient, amount, expiry, payment nonce and minimum age.
    function verifyOrderAge(
        bytes32 orderHash, bytes32 nonce, uint256 expiresAt,
        bytes calldata proof, uint256[8] calldata inputs
    ) external view returns (bool) {
        if (orderHash == bytes32(0) || nonce == bytes32(0) || proof.length != 384
            || expiresAt <= block.timestamp || expiresAt < ORDER_DURATION
            || verifier.codehash != verifierCodeHash) return false;
        uint256 referenceTime = expiresAt - ORDER_DURATION;
        if (referenceTime > block.timestamp || inputs[6] != referenceTime || inputs[7] != expiresAt
            || inputs[0] != uint256(orderHash) >> 128 || inputs[1] != uint128(uint256(orderHash))
            || inputs[2] != uint256(nonce) >> 128 || inputs[3] != uint128(uint256(nonce))
            || inputs[4] > type(uint128).max || inputs[5] > type(uint128).max) return false;
        bytes32 rootHash = bytes32((inputs[4] << 128) | inputs[5]);
        if (!_rootValid(rootHash, referenceTime, expiresAt)) return false;
        try IAgeGroth16Verifier(verifier).verifyProof(proof, inputs) { return true; }
        catch { return false; }
    }

    // SHA-256 of the 256-byte, big-endian RSA modulus from fingerprint-pinned
    // official J-LIS signing roots (see docs/SOURCES.md). Not a person's key.
    // No caller, card, model, admin or server can add a trust root at runtime.
    function _rootValid(bytes32 rootHash, uint256 start, uint256 end) internal pure virtual returns (bool) {
        if (rootHash == 0xa5fad04a2d6cbb52ce03a55106a6e23be4fa4a771bb0bf81401833afc410b15e)
            return start >= 1568504516 && end <= 1884092399;
        if (rootHash == 0x9ec2093f1d4c86f0e22cd2b45140428437eba9591e979fa688428b71c241011c)
            return start >= 1689468627 && end <= 2005052399;
        return false;
    }
}
