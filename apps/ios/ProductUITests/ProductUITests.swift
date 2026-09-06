import XCTest

/// Launches the real app without injected wallets, model responses, or proof outcomes.
@MainActor
final class ProductUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["talk-button"].waitForExistence(timeout: 15))
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func assertVisibleControls(_ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        for id in ["talk-button", "rest-button", "open-conversation", "open-settings", "open-activity"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists, id)
            XCTAssertTrue(button.isHittable, id)
            XCTAssertTrue(window.contains(button.frame), "Clipped control: \(id)")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
    }
    func testPortraitHomeDoesNotStartSensorsAndControlsRemainAccessible() throws {
        let app = launch()
        assertVisibleControls(app)
        XCTAssertTrue(app.staticTexts["カメラ停止中"].exists)
        capture("01-home-portrait")
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription])
        app.buttons["rest-button"].tap()
        XCTAssertTrue(app.staticTexts["ひと休みしています。"].waitForExistence(timeout: 3))
        capture("02-resting")
    }
    func testConversationSettingsAndEmptyActivityAreRealScreens() throws {
        let app = launch()
        app.buttons["open-conversation"].tap()
        XCTAssertTrue(app.textFields["message-input"].waitForExistence(timeout: 5)
            || app.textViews["message-input"].waitForExistence(timeout: 5))
        capture("03-conversation-empty")
        app.buttons["close-sheet"].tap()
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["toggle-camera"].waitForExistence(timeout: 5))
        capture("04-settings")
        app.buttons["close-sheet"].tap()
        app.buttons["open-activity"].tap()
        XCTAssertTrue(app.staticTexts["まだ、何も実行していません。"].waitForExistence(timeout: 5))
        capture("05-activity-empty")
    }
    func testLandscapeControlsAreNotClipped() {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["talk-button"].waitForExistence(timeout: 5))
        // Wait for UIKit's actual orientation transition, not fabricated view state.
        let predicate = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
        expectation(for: predicate, evaluatedWith: nil)
        waitForExpectations(timeout: 8)
        capture("06-home-landscape")
        assertVisibleControls(app)
    }
}
