import Foundation
#if canImport(MateAgeRuntime)
import MateAgeRuntime
#endif

public enum MateAgeNativeError: Error, Equatable {
    case unavailable, rejected(Int32), invalidOutput
}
public struct MateAgeNativeResult: Sendable {
    public let proof: Data
    public let publicInputs: [Data]
}
/// This adapter has no card, network, model or wallet access. Call from a
/// background actor, with setup-file hashes checked by the application first.
public enum MateAgeNative {
    public static var available: Bool {
        #if canImport(MateAgeRuntime)
        return true
        #else
        return false
        #endif
    }
    public static func prove(proverPath: String, verifierPath: String, input: Data) throws -> MateAgeNativeResult {
        #if canImport(MateAgeRuntime)
        guard (2...40000).contains(input.count), !proverPath.utf8.contains(0), !verifierPath.utf8.contains(0) else {
            throw MateAgeNativeError.invalidOutput
        }
        var output = [UInt8](repeating: 0, count: 640)
        let code = proverPath.withCString { prover in verifierPath.withCString { verifier in
            input.withUnsafeBytes { bytes in output.withUnsafeMutableBufferPointer { result in
                mate_age_prove(prover, verifier, bytes.bindMemory(to: UInt8.self).baseAddress,
                               input.count, result.baseAddress, result.count)
            } }
        } }
        guard code == 0 else { throw MateAgeNativeError.rejected(code) }
        return MateAgeNativeResult(proof: Data(output.prefix(384)),
            publicInputs: (0..<8).map { Data(output[(384 + $0 * 32)..<(416 + $0 * 32)]) })
        #else
        throw MateAgeNativeError.unavailable
        #endif
    }
}
