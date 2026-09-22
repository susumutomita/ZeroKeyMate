import CryptoKit
import Foundation
import MateAgeProof

/// Experimental synthetic benchmark only. The purchase API has no route here.
actor AgeBenchmarkService {
    enum Backend: String, CaseIterable, Codable, Identifiable, Sendable {
        case groth16 = "Groth16", whir = "WHIR"
        var id: String { rawValue }
        var native: MateAgeBenchmarkBackend { self == .whir ? .whir : .groth16 }
    }
    struct Report: Sendable, Codable, Identifiable {
        let id: UUID
        let backend: Backend
        let operatingSystem: String
        let device: String
        let thermalBefore: Int
        let thermalAfter: Int
        let preparationMicroseconds: UInt64
        let native: MateAgeNativeBenchmark
        let syntheticOnly: Bool
        let physicalDevice: Bool
        let appBuild: String
        let sourceRevision: String
        let statementSHA256: String
        let fixtureSHA256: String
    }
    static let sourceRevision = "dd237e542403302186c8de4bd10df6e5c9b6725a"
    static let fixtureSHA256 = "464d1b4f7bf30c0547bf2bd2372c58ac95053c22b12b75f96593e4e18597be31"
    static let whirProverSHA256 = "2cd18281f6016db3eca60f857d846b72067b4d159d5ff667ecdff7a744d604cb"
    static let whirVerifierSHA256 = "fb02ce2d033667acdaffee84139da11223c91f1ebe5cbe8606193c67fbf838cc"
    private var checked: [Backend: (URL, URL)] = [:]

    func run(_ backend: Backend, bundle: Bundle = .main) throws -> Report {
        guard MateAgeNative.available else { throw AgeProofFailure.resources }
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let resources = try prepare(backend, bundle: bundle)
        let preparation = Self.microseconds(start.duration(to: .now))
        let before = ProcessInfo.processInfo.thermalState.rawValue
        // Fixed synthetic input is compiled into the ABI. No card data, wallet,
        // network request or proof file can be supplied to or returned by it.
        let result = try MateAgeNative.benchmark(proverPath: resources.0.path,
            verifierPath: resources.1.path, backend: backend.native)
        try Task.checkCancellation() // An in-flight native call finishes, then discards.
        var machine = utsname(); uname(&machine)
        let device = withUnsafeBytes(of: &machine.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        #if targetEnvironment(simulator)
        let physical = false
        #else
        let physical = true
        #endif
        return Report(id: UUID(), backend: backend,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, device: device,
            thermalBefore: before, thermalAfter: ProcessInfo.processInfo.thermalState.rawValue,
            preparationMicroseconds: preparation, native: result, syntheticOnly: true,
            physicalDevice: physical, appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            sourceRevision: Self.sourceRevision, statementSHA256: AgeProofPins.statementSHA256,
            fixtureSHA256: Self.fixtureSHA256)
    }
    func available(_ backend: Backend, bundle: Bundle = .main) -> Bool {
        let name = backend == .whir ? "age-benchmark-whir" : "age"
        return MateAgeNative.available && bundle.url(forResource: name, withExtension: "pkp") != nil
            && bundle.url(forResource: name, withExtension: "pkv") != nil
    }
    private func prepare(_ backend: Backend, bundle: Bundle) throws -> (URL, URL) {
        if let existing = checked[backend] { return existing }
        let name = backend == .whir ? "age-benchmark-whir" : "age"
        guard let prover = bundle.url(forResource: name, withExtension: "pkp"),
              let verifier = bundle.url(forResource: name, withExtension: "pkv") else { throw AgeProofFailure.resources }
        let expectedProver = backend == .whir ? Self.whirProverSHA256 : AgeProofPins.proverSHA256
        let expectedVerifier = backend == .whir ? Self.whirVerifierSHA256 : AgeProofPins.verifierSHA256
        guard try hash(prover) == expectedProver, try hash(verifier) == expectedVerifier else {
            throw AgeProofFailure.resources
        }
        checked[backend] = (prover, verifier); return (prover, verifier)
    }
    private func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var digest = SHA256()
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func microseconds(_ duration: Duration) -> UInt64 {
        let parts = duration.components
        return UInt64(max(0, parts.seconds * 1_000_000 + parts.attoseconds / 1_000_000_000_000))
    }
}
