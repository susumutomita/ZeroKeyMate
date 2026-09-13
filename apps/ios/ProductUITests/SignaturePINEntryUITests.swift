import XCTest

/// Operates the exact purchase field/button in an explicitly labeled simulator
/// host. It has no checkout, card, wallet or payment service to call.
@MainActor final class SignaturePINEntryUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-mate-card-entry-ui-check", "-mate-companion-language", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Card input test — no card or purchase"].waitForExistence(timeout: 10))
        return app
    }
    func testEmptyAndFourDigitInputRemainTappableAndExplainWhatIsNeeded() {
        let app = launch()
        let scan = app.buttons["shop-tap-card"]
        XCTAssertTrue(scan.isEnabled)
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        XCTAssertTrue(app.staticTexts["Enter your signature password to start the scan."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let field = app.secureTextFields["shop-signature-pin"]
        field.typeText("1234")
        XCTAssertTrue(scan.isEnabled)
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        XCTAssertTrue(app.staticTexts["Use the 6–16 character signature password, not the four-digit PIN."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["accepted-inputs"].label, "Accepted inputs: 0")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "card-pin-actionable-validation"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testValidPINButtonWorksWithKeyboardAndFromItsVisibleEdge() {
        let app = launch()
        let field = app.secureTextFields["shop-signature-pin"]
        field.tap(); field.typeText("ab1234") // Synthetic test input, never sent to NFC.
        let scan = app.buttons["shop-tap-card"]
        XCTAssertTrue(scan.isHittable)
        XCTAssertTrue(scan.isEnabled)
        scan.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Accepted inputs: 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Signature password")
        scan.tap()
        XCTAssertTrue(app.staticTexts["Enter your signature password to start the scan."].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["accepted-inputs"].label, "Accepted inputs: 1")
    }
}
