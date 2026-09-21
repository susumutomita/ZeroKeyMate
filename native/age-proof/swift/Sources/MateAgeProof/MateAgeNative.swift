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
    public let timing: MateAgeNativeTiming
}
/// Local-only durations. Witness construction and Groth16 are one upstream
/// call, so this does not claim an isolated cryptographic primitive benchmark.
public struct MateAgeNativeTiming: Sendable, Codable, Equatable {
    public let version: UInt64
    public let workerThreads: UInt64
    public let totalMicroseconds: UInt64
    public let proverLoadMicroseconds: UInt64
    public let inputParseMicroseconds: UInt64
    public let witnessAndProofMicroseconds: UInt64
    public let verifierLoadMicroseconds: UInt64
    public let verificationMicroseconds: UInt64
    public let encodingMicroseconds: UInt64
}
/// This adapter has no card, network, model or wallet access. Call from a
/// background actor, with setup-file hashes checked by the application first.
public enum MateAgeNative {
    public static func keccak256(_ input: Data) throws -> Data {
        #if canImport(MateAgeRuntime)
        var output = [UInt8](repeating: 0, count: 32)
        let code = input.withUnsafeBytes { bytes in output.withUnsafeMutableBufferPointer { result in
            mate_age_keccak256(bytes.bindMemory(to: UInt8.self).baseAddress, input.count, result.baseAddress, result.count)
        } }
        guard code == 0 else { throw MateAgeNativeError.rejected(code) }
        return Data(output)
        #else
        throw MateAgeNativeError.unavailable
        #endif
    }
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
        var metrics = MateAgeMetrics()
        let code = proverPath.withCString { prover in verifierPath.withCString { verifier in
            input.withUnsafeBytes { bytes in output.withUnsafeMutableBufferPointer { result in
                mate_age_prove_measured(prover, verifier, bytes.bindMemory(to: UInt8.self).baseAddress,
                               input.count, result.baseAddress, result.count, &metrics)
            } }
        } }
        guard code == 0 else { throw MateAgeNativeError.rejected(code) }
        let durations = [metrics.prover_load_us, metrics.input_parse_us, metrics.witness_and_proof_us,
                         metrics.verifier_load_us, metrics.verify_us, metrics.encode_us]
        guard metrics.version == 1, metrics.worker_threads == 2,
              durations.allSatisfy({ $0 <= metrics.total_us }),
              durations.reduce(UInt64(0), { $0.addingReportingOverflow($1).overflow ? UInt64.max : $0 + $1 }) <= metrics.total_us
        else { throw MateAgeNativeError.invalidOutput }
        return MateAgeNativeResult(proof: Data(output.prefix(384)),
            publicInputs: (0..<8).map { Data(output[(384 + $0 * 32)..<(416 + $0 * 32)]) },
            timing: MateAgeNativeTiming(version: metrics.version, workerThreads: metrics.worker_threads,
                totalMicroseconds: metrics.total_us, proverLoadMicroseconds: metrics.prover_load_us,
                inputParseMicroseconds: metrics.input_parse_us, witnessAndProofMicroseconds: metrics.witness_and_proof_us,
                verifierLoadMicroseconds: metrics.verifier_load_us, verificationMicroseconds: metrics.verify_us,
                encodingMicroseconds: metrics.encode_us))
        #else
        throw MateAgeNativeError.unavailable
        #endif
    }
}
