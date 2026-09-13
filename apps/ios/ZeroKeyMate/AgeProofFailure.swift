import Foundation
import MateCore
import MateAgeProof

/// Fixed diagnostic categories only. Never retain an underlying error, card
/// field, witness, path or native panic text in a saved order or a UI message.
enum AgeProofFailure: String, Codable, Error, CaseIterable {
    case interrupted = "AGE-I"
    case resources = "AGE-R"
    case orderWindow = "AGE-W"
    case certificate = "AGE-C"
    case key = "AGE-K"
    case authentication = "AGE-A"
    case nativeArguments = "AGE-N1"
    case nativeSetup = "AGE-N2"
    case nativeInput = "AGE-N3"
    case nativeConstraints = "AGE-N4"
    case nativeVerification = "AGE-N5"
    case nativeOutput = "AGE-N6"
    case nativeInterrupted = "AGE-N7"
    case nativeBusy = "AGE-N8"
    case output = "AGE-O"
    case unknown = "AGE-U"

    static func classify(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if let native = error as? MateAgeNativeError {
            switch native {
            case .unavailable: return .resources
            case .invalidOutput: return .output
            case .rejected(let code):
                return [1: .nativeArguments, 2: .nativeSetup, 3: .nativeInput,
                        4: .nativeConstraints, 5: .nativeVerification, 6: .nativeOutput,
                        7: .nativeInterrupted, 8: .nativeBusy][Int(code)] ?? .unknown
            }
        }
        if let witness = error as? JPKIAgeWitnessError {
            switch witness {
            case .invalidOrderWindow: return .orderWindow
            case .unsupportedCertificate: return .certificate
            case .unsupportedKey: return .key
            }
        }
        if error is JPKIVerificationError { return .authentication }
        return .unknown
    }

    var explanation: String {
        switch self {
        case .orderWindow: return "The order expired before its age proof was ready. Nothing was paid."
        case .resources, .nativeSetup: return "Mate could not load its age proof engine. Reading the card again will not fix this. Nothing was paid."
        case .certificate, .key: return "Mate cannot yet prove the age on this card's certificate. Nothing was paid."
        case .nativeBusy: return "The age proof engine is still finishing another attempt. Nothing was paid."
        case .interrupted, .nativeInterrupted: return "Age proof creation stopped before it finished. Nothing was paid."
        default: return "Card reading finished, but age proof creation failed on this iPhone. Nothing was paid."
        }
    }
}
