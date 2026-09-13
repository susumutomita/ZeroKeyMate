import XCTest
import MateCore
@testable import ZeroKeyMate

@MainActor final class SignaturePINEntryTests: XCTestCase {
    func testIncompletePINExplainsTheProblemWithoutCallingScanner() {
        let entry = SignaturePINEntry()
        for pin in ["", "1234", "AB12", "AB1234567890123456", "ＡＢ１２３４", "ABCDEF", "123456", " AB1234"] {
            entry.pin = pin
            entry.submit(busy: false) { _ in XCTFail("Invalid input reached the scanner") }
            XCTAssertNotNil(entry.feedback)
            XCTAssertTrue(entry.focusRequested)
            XCTAssertEqual(entry.pin, pin, "Never silently change a credential")
            let text = entry.feedback ?? ""
            XCTAssertNotEqual(L10n.text(text, language: .japanese), text)
        }
    }
    func testValidInputIsHandedOffOnceAndClearedBeforeScannerStarts() {
        let entry = SignaturePINEntry()
        entry.pin = "AB1234" // Synthetic input only.
        var count = 0
        entry.submit(busy: false) { pin in
            count += 1
            XCTAssertEqual(pin, "AB1234")
            XCTAssertTrue(JPKICardReader.validSigningPIN(pin))
            XCTAssertTrue(entry.pin.isEmpty)
            XCTAssertNil(entry.feedback)
            XCTAssertFalse(entry.focusRequested)
        }
        entry.submit(busy: false) { _ in XCTFail("Repeated the cleared PIN") }
        XCTAssertEqual(count, 1)
    }
    func testLowercaseIsConvertedBeforeValidationAndCardHandoff() {
        for input in ["ab1234", "aB1234", "AB1234"] {
            let entry = SignaturePINEntry()
            entry.pin = input
            XCTAssertEqual(entry.pin, "AB1234")
            var received = false
            entry.submit(busy: false) { pin in
                XCTAssertEqual(pin, "AB1234")
                received = true
            }
            XCTAssertTrue(received)
            XCTAssertTrue(entry.pin.isEmpty)
        }
        XCTAssertEqual(SignaturePINEntry.uppercaseASCII("ßａｂ 12"), "ßａｂ 12")
    }
    func testBusyCheckoutCannotStartAnotherRead() {
        let entry = SignaturePINEntry()
        entry.pin = "AB1234"
        entry.submit(busy: true) { _ in XCTFail("Started a parallel read") }
        XCTAssertEqual(entry.pin, "AB1234")
        entry.clear()
        XCTAssertTrue(entry.pin.isEmpty)
    }
}
