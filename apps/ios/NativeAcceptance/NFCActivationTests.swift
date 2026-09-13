import XCTest
import CoreNFC

#if !targetEnvironment(simulator)
/// An explicitly selected hardware probe. It only opens and closes CoreNFC's
/// system sheet: no PIN, connection, APDU, card payload, camera or wallet access.
@MainActor private final class NFCActivationProbe: NSObject, @preconcurrency NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    var complete: ((Bool, Int?) -> Void)?
    func start() {
        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main)
        session?.alertMessage = "Checking the scanner. No card or PIN is needed."
        session?.begin()
    }
    func cancel() { let previous = session; session = nil; previous?.invalidate() }
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        guard self.session === session else { return }
        complete?(true, nil); cancel()
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard self.session === session else { return }
        // System error code only. Never print error descriptions or tag data.
        complete?(false, (error as NSError).code); cancel()
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        // Deliberately do not inspect/connect to a nearby card.
        cancel()
    }
}
#endif

final class NFCActivationTests: XCTestCase {
    @MainActor func testExplicitPhysicalScannerActivationWithoutCardData() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Explicit physical iPhone probe; CoreNFC is absent from Simulator.")
#else
        // An isolated, explicitly selected test run sets this flag. Normal CI
        // and native proof tests must never start a reader in the background.
        guard ProcessInfo.processInfo.environment["MATE_NFC_ACTIVATION_ONLY"] == "1" else {
            throw XCTSkip("Select the NFC-only hardware probe explicitly.")
        }
        XCTAssertTrue(NFCTagReaderSession.readingAvailable)
        let active = expectation(description: "System NFC scanner activated")
        let probe = NFCActivationProbe()
        var result: Bool?, code: Int?
        probe.complete = { success, errorCode in
            guard result == nil else { return }
            result = success; code = errorCode; active.fulfill()
        }
        defer { probe.cancel() }
        probe.start()
        await fulfillment(of: [active], timeout: 12)
        XCTAssertEqual(result, true, "NFC activation failed; system code: \(code.map(String.init) ?? "none")")
#endif
    }
}
