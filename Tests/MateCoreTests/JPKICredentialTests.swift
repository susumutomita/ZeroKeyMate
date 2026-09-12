import XCTest
@testable import MateCore
#if canImport(Security) && canImport(CryptoKit)

final class JPKICredentialTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func fixture(_ name: String, ext: String = "der") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "JPKI")))
    }
    private func challenge(order: UInt8 = 1, nonce: UInt8 = 2) throws -> JPKIChallenge {
        try JPKIChallenge(orderHash: Data(repeating: order, count: 32), nonce: Data(repeating: nonce, count: 32))
    }
    private func authentication(_ certificate: Data? = nil) throws -> UnverifiedJPKIAuthentication {
        try .init(certificate: certificate ?? fixture("card"), signature: fixture("card-signature", ext: "bin"))
    }
    func testActualRSACertificateAndCardSignatureUnderSyntheticRoot() throws {
        let credential = try JPKICredentialVerifier.verify(authentication(), challenge: challenge(), now: now, roots: [fixture("root")])
        XCTAssertEqual(credential.birthDate, try UnverifiedCardBirthDate(ascii: Data("19900102".utf8)))
        XCTAssertFalse(credential.revocationChecked)
    }
    func testPublicVerifierRejectsSyntheticGovernmentAndChecksBundledFingerprints() throws {
        XCTAssertEqual(try JPKICredentialVerifier.pinnedRoots().count, 2)
        XCTAssertThrowsError(try JPKICredentialVerifier.verify(authentication(), challenge: challenge(), now: now))
    }
    func testTamperedBirthDateAndCertificateSignatureAreRejected() throws {
        let root = try fixture("root")
        var tamperedDate = try fixture("card")
        let dateRange = try XCTUnwrap(tamperedDate.range(of: Data("419900102".utf8)))
        tamperedDate.replaceSubrange(dateRange, with: Data("419800102".utf8))
        var tamperedSignature = try fixture("card"); tamperedSignature[tamperedSignature.count - 1] ^= 1
        for certificate in [tamperedDate, tamperedSignature] {
            XCTAssertThrowsError(try JPKICredentialVerifier.verify(authentication(certificate), challenge: challenge(), now: now, roots: [root]))
        }
    }
    func testCardSignatureCannotBeReplayedForAnotherOrderOrNonce() throws {
        for changed in [try challenge(order: 3), try challenge(nonce: 4)] {
            XCTAssertThrowsError(try JPKICredentialVerifier.verify(authentication(), challenge: changed, now: now, roots: [fixture("root")])) {
                XCTAssertEqual($0 as? JPKIVerificationError, .invalidCardSignature)
            }
        }
    }
    func testExpiredAndNotYetValidCertificatesFailOffline() throws {
        for date in [Date(timeIntervalSince1970: 1_600_000_000), Date(timeIntervalSince1970: 2_000_000_000)] {
            XCTAssertThrowsError(try JPKICredentialVerifier.verify(authentication(), challenge: challenge(), now: date, roots: [fixture("root")]))
        }
    }
    func testDuplicateUnknownDatesAndTrailingCertificateBytesFail() throws {
        for certificate in [try fixture("duplicate-date"), try fixture("unknown-date"), try fixture("card") + Data([0])] {
            XCTAssertThrowsError(try JPKICertificateFields(certificate))
        }
    }
    func testAuthenticatedBirthDateIsNotAnAgeApproval() throws {
        let credential = try JPKICredentialVerifier.verify(authentication(fixture("underage")), challenge: challenge(), now: now, roots: [fixture("root")])
        XCTAssertEqual(credential.birthDate.year, 2020)
        XCTAssertFalse(credential.revocationChecked)
    }
    func testStrictDERLengthsRejectIndefiniteOverlongAndTruncatedData() {
        for value: [UInt8] in [[0x30,0x80,0,0], [0x30,0x81,1,0], [0x30,0x82,0,128], [0x30,0x82,0xFF,0xFF], [0x30,2,0]] {
            XCTAssertThrowsError(try DERNode.single(Data(value), tag: 0x30))
        }
    }
    func testChallengeRequiresFullNonzeroOrderAndNonce() {
        XCTAssertThrowsError(try JPKIChallenge(orderHash: Data([1]), nonce: Data(repeating: 2, count: 32)))
        XCTAssertThrowsError(try JPKIChallenge(orderHash: Data(repeating: 1, count: 32), nonce: Data(repeating: 0, count: 32)))
    }
}

@MainActor final class JPKICardReaderTests: XCTestCase {
    private func challenge() throws -> JPKIChallenge { try .init(orderHash: Data(repeating: 1, count: 32), nonce: Data(repeating: 2, count: 32)) }
    func testWrongSigningPINIsNeverRetriedAndCertificateIsNeverRead() async throws {
        var commands: [MyNumberCardCommand] = []
        do {
            _ = try await JPKICardReader.authenticate(pin: "ABC123", challenge: challenge()) { command in
                commands.append(command)
                return command.instruction == 0x20 ? .init(sw1: 0x63, sw2: 0xC4) : .init()
            }
            XCTFail("Rejected PIN must not proceed")
        } catch { XCTAssertEqual(error as? MyNumberCardError, .pinRejected(remainingAttempts: 4)) }
        XCTAssertEqual(commands.filter { $0.instruction == 0x20 }.count, 1)
        XCTAssertFalse(commands.contains { $0.instruction == 0xB0 || $0.instruction == 0x2A })
        XCTAssertEqual(commands.first?.data, JPKICardReader.applicationID)
    }
    func testInvalidPINDoesNotContactCard() async throws {
        for pin in ["1234", "abcdef", "ABCDEF", "123456", "ＡBC123", "abc123", " ABC123", String(repeating: "A1", count: 9)] {
            do {
                _ = try await JPKICardReader.authenticate(pin: pin, challenge: challenge()) { _ in XCTFail("Unexpected card operation"); return .init() }
                XCTFail("Invalid signing PIN accepted")
            } catch { XCTAssertEqual(error as? MyNumberCardError, .invalidPIN) }
        }
    }
    func testOversizedCertificateHeaderNeverReadsPagesOrSigns() async throws {
        var reads = 0
        do {
            _ = try await JPKICardReader.authenticate(pin: "ABC123", challenge: challenge()) { command in
                if command.instruction == 0xB0 { reads += 1; return .init(data: Data([0x30,0x82,0xFF,0xFF])) }
                XCTAssertNotEqual(command.instruction, 0x2A)
                return .init()
            }
            XCTFail("Oversized certificate accepted")
        } catch { XCTAssertEqual(error as? MyNumberCardError, .malformedResponse) }
        XCTAssertEqual(reads, 1)
    }
}
#endif
