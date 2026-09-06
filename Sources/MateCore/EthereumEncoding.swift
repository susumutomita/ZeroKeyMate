import Foundation

/// Ethereum uses Keccak-256 (suffix 0x01), not the FIPS SHA3-256 suffix 0x06.
/// Keccak-f[1600]: https://keccak.team/keccak_specs_summary.html
/// This is used for transaction identifiers, selectors and ENS namehash, never for keys.
public enum EthereumKeccak {
    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]
    private static let rotations = [
        0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39,
        41, 45, 15, 21, 8, 18, 2, 61, 56, 14
    ]
    private static func rotate(_ value: UInt64, by bits: Int) -> UInt64 {
        bits == 0 ? value : (value << bits) | (value >> (64 - bits))
    }
    private static func permute(_ state: inout [UInt64]) {
        for constant in roundConstants {
            var columns = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 { for y in 0..<5 { columns[x] ^= state[x + 5 * y] } }
            for x in 0..<5 {
                let delta = columns[(x + 4) % 5] ^ rotate(columns[(x + 1) % 5], by: 1)
                for y in 0..<5 { state[x + 5 * y] ^= delta }
            }
            var moved = [UInt64](repeating: 0, count: 25)
            for x in 0..<5 { for y in 0..<5 {
                moved[y + 5 * ((2 * x + 3 * y) % 5)] = rotate(state[x + 5 * y], by: rotations[x + 5 * y])
            } }
            for x in 0..<5 { for y in 0..<5 {
                state[x + 5 * y] = moved[x + 5 * y] ^ ((~moved[(x + 1) % 5 + 5 * y]) & moved[(x + 2) % 5 + 5 * y])
            } }
            state[0] ^= constant
        }
    }
    public static func digest(_ input: Data) -> Data {
        let rate = 136
        var bytes = Array(input)
        bytes.append(0x01)
        while bytes.count % rate != rate - 1 { bytes.append(0) }
        bytes.append(0x80)
        // The suffix and final bit must share the final byte when only one byte remains.
        if input.count % rate == rate - 1 {
            bytes = Array(input); bytes.append(0x81)
        }
        var state = [UInt64](repeating: 0, count: 25)
        for offset in stride(from: 0, to: bytes.count, by: rate) {
            for index in 0..<rate { state[index / 8] ^= UInt64(bytes[offset + index]) << ((index % 8) * 8) }
            permute(&state)
        }
        return Data((0..<32).map { UInt8(truncatingIfNeeded: state[$0 / 8] >> (($0 % 8) * 8)) })
    }
}

/// Minimal, bounded ABI surface for the exact functions exposed by Mate.
public enum EthereumABI {
    public enum Argument { case word(Data), dynamic(Data) }
    public static func word(_ value: UInt64) -> Data { Data(repeating: 0, count: 24) + CanonicalBytes.u64(value) }
    public static func addressWord(_ value: String) throws -> Data {
        try Data(repeating: 0, count: 12) + CanonicalBytes.hex(value, count: 20)
    }
    public static func call(_ signature: String, _ arguments: [Argument]) throws -> String {
        var head = Data(), tail = Data()
        for argument in arguments {
            switch argument {
            case .word(let value):
                guard value.count == 32 else { throw MandateError.invalidAction }; head += value
            case .dynamic(let value):
                guard value.count <= 8192 else { throw MandateError.invalidAction }
                head += word(UInt64(arguments.count * 32 + tail.count))
                tail += word(UInt64(value.count)) + value
                tail += Data(repeating: 0, count: (32 - value.count % 32) % 32)
            }
        }
        return CanonicalBytes.hexString(Data(EthereumKeccak.digest(Data(signature.utf8)).prefix(4)) + head + tail)
    }
    public static func decimalWord(_ value: String) throws -> Data {
        guard !value.isEmpty, value.count <= 78, value.utf8.allSatisfy({ (48...57).contains($0) }),
              value.count == 1 || value.first != "0" else { throw MandateError.invalidAmount }
        var bytes=[UInt8](repeating:0,count:32)
        for digit in value.utf8 {
            var carry=UInt16(digit-48)
            for index in stride(from:31,through:0,by:-1) {
                let product=UInt16(bytes[index])*10+carry
                bytes[index]=UInt8(truncatingIfNeeded:product);carry=product>>8
            }
            guard carry==0 else { throw MandateError.invalidAmount }
        }
        return Data(bytes)
    }
    public static func unsignedWord(_ bytes: Data) throws -> UInt64 {
        guard bytes.count==32,bytes.prefix(24).allSatisfy({$0==0}) else { throw MandateError.invalidAmount }
        return bytes.suffix(8).reduce(0){($0<<8)|UInt64($1)}
    }
    public static func decodeAddress(_ hex: String) throws -> String {
        let bytes = try CanonicalBytes.hex(hex, count: 32)
        guard bytes.prefix(12).allSatisfy({ $0 == 0 }) else { throw MandateError.invalidHex }
        return CanonicalBytes.hexString(Data(bytes.suffix(20)))
    }
    public static func decodeText(_ hex: String) throws -> String {
        guard hex.utf8.count >= 130, hex.utf8.count <= 2 + 2 * 8256, (hex.utf8.count - 2) % 2 == 0 else { throw MandateError.invalidHex }
        let bytes = try CanonicalBytes.hex(hex, count: (hex.utf8.count - 2) / 2)
        guard bytes.prefix(32) == word(32), bytes[32..<56].allSatisfy({ $0 == 0 }) else { throw MandateError.invalidHex }
        let length = bytes[56..<64].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length <= 8192, bytes.count >= 64 + Int(length),
              let result = String(data: bytes.subdata(in: 64..<64 + Int(length)), encoding: .utf8) else { throw MandateError.invalidHex }
        return result
    }
    /// Deliberately accepts a small already-normalized ASCII subset; never approximates ENS normalization.
    public static func labels(_ name: String) throws -> [String] {
        guard !name.isEmpty, name.utf8.count <= 253, name == name.lowercased() else { throw MandateError.invalidAction }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }) else { throw MandateError.invalidAction }
        return labels
    }
    public static func dns(_ name: String) throws -> Data {
        var bytes = Data()
        for label in try labels(name) { bytes.append(UInt8(label.utf8.count)); bytes += Data(label.utf8) }
        bytes.append(0); return bytes
    }
    public static func namehash(_ name: String) throws -> Data {
        if name.isEmpty { return Data(repeating: 0, count: 32) }
        return try labels(name).reversed().reduce(Data(repeating: 0, count: 32)) {
            EthereumKeccak.digest($0 + EthereumKeccak.digest(Data($1.utf8)))
        }
    }
}

/// EIP-712 digest of a grant, independently recomputed before accepting server receipts.
public enum MandateDigest {
    public static func grant(_ grant: MandateGrant, chainID: UInt64, vault: String) throws -> String {
        func text(_ value: String) -> Data { EthereumKeccak.digest(Data(value.utf8)) }
        let domain=try text("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
            + text("ZeroKey Mate") + text("1") + EthereumABI.word(chainID) + EthereumABI.addressWord(vault)
        let message=try text("Grant(address owner,address agent,bytes32 policyHash,uint64 validUntil,uint256 nonce)")
            + EthereumABI.addressWord(grant.owner) + EthereumABI.addressWord(grant.agent)
            + CanonicalBytes.hex(grant.policyHash,count:32) + EthereumABI.word(grant.validUntil) + EthereumABI.decimalWord(grant.nonce)
        return CanonicalBytes.hexString(EthereumKeccak.digest(Data([0x19,0x01]) + EthereumKeccak.digest(domain) + EthereumKeccak.digest(message)))
    }
}
