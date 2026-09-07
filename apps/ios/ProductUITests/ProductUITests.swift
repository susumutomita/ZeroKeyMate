import XCTest

/// Launches the real app without injected wallets, model responses, or proof outcomes.
@MainActor
final class ProductUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["talk-button"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["talk-button"].isHittable)
        return app
    }
    private func closeSheet(_ app: XCUIApplication) {
        app.buttons["close-sheet"].tap()
        XCTAssertTrue(app.buttons["close-sheet"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-conversation"].isHittable)
    }
    private func tapPadding(_ button: XCUIElement) {
        // A reported 44pt frame alone does not prove the transparent padding
        // accepts touches. Exercise the label's actual interaction shape.
        XCTAssertTrue(button.isHittable)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
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
        XCTAssertTrue(app.staticTexts["Camera off"].exists)
        capture("01-home-portrait")
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription])
        app.buttons["rest-button"].tap()
        XCTAssertTrue(app.staticTexts["Taking a rest."].waitForExistence(timeout: 3))
        capture("02-resting")
    }
    func testConversationSettingsAndEmptyActivityAreRealScreens() throws {
        let app = launch()
        app.buttons["open-conversation"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "message-input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        capture("03-conversation-empty")
        closeSheet(app)
        tapPadding(app.buttons["open-conversation"])
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        closeSheet(app)
        tapPadding(app.buttons["open-settings"])
        XCTAssertTrue(app.buttons["toggle-camera"].waitForExistence(timeout: 5))
        capture("04-settings")
        closeSheet(app)
        tapPadding(app.buttons["open-activity"])
        XCTAssertTrue(app.staticTexts["No executions yet."].waitForExistence(timeout: 5))
        capture("05-activity-empty")
    }
    func testLocalProofPreflightDoesNotPretendToGenerateProof() {
        let app = launch()
        tapPadding(app.buttons["open-local-proof"])
        XCTAssertTrue(app.buttons["generate-local-proof"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["generate-local-proof"].isHittable)
        let permission=app.switches["Allow translation"]
        XCTAssertEqual(permission.value as? String,"1")
        // SwiftUI exposes a full row, but the actual UISwitch is on its trailing edge.
        permission.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        let disabled=NSPredicate(format:"value == %@","0")
        expectation(for:disabled,evaluatedWith:permission)
        waitForExpectations(timeout:5)
        app.buttons["generate-local-proof"].tap()
        XCTAssertTrue(app.staticTexts["No proof generated. This service is not allowed."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Original proof accepted"].exists)
        capture("07-local-proof-preflight")
    }
    func testNativeLocalProofCanBeGeneratedAndPreparedForSharing() throws {
#if MATE_NATIVE_PROOFS
        let app=launch()
        tapPadding(app.buttons["open-local-proof"])
        app.buttons["generate-local-proof"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["local-proof-ready"].waitForExistence(timeout:120))
        let prepare=app.buttons["Prepare proof file for sharing"]
        for _ in 0..<6 {
            if prepare.exists && prepare.isHittable && prepare.frame.maxY < app.buttons["generate-local-proof"].frame.minY {break}
            app.swipeUp()
        }
        XCTAssertTrue(prepare.isHittable)
        XCTAssertLessThan(prepare.frame.maxY,app.buttons["generate-local-proof"].frame.minY)
        XCTAssertTrue(app.staticTexts["Original proof accepted"].exists)
        XCTAssertTrue(app.staticTexts["Modified proof rejected"].exists)
        prepare.tap()
        XCTAssertTrue(app.buttons["Share proof file"].waitForExistence(timeout:5))
        capture("09-native-proof-ready-to-share")
#else
        throw XCTSkip("This source-only build explicitly has no native prover. Run the native acceptance workflow.")
#endif
    }
    func testLanguageSwitchPersistsAndLocalProofRefusalIsTranslated() {
        let app=launch()
        app.buttons["open-settings"].tap()
        let picker=app.segmentedControls["app-language"]
        XCTAssertTrue(picker.waitForExistence(timeout:5))
        picker.buttons["日本語"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout:5))
        closeSheet(app)
        XCTAssertTrue(app.staticTexts["休憩しています。"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["カメラ停止"].exists)
        tapPadding(app.buttons["open-local-proof"])
        let permission=app.switches["翻訳を許可"]
        XCTAssertTrue(permission.waitForExistence(timeout:5))
        permission.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        expectation(for:NSPredicate(format:"value == %@","0"),evaluatedWith:permission)
        waitForExpectations(timeout:5)
        app.buttons["generate-local-proof"].tap()
        XCTAssertTrue(app.staticTexts["証明は生成していません。このサービスは許可されていません。"].waitForExistence(timeout:5))
        capture("08-japanese-proof-refusal")
        closeSheet(app)
        app.terminate();app.launch()
        XCTAssertTrue(app.staticTexts["カメラ停止"].waitForExistence(timeout:15))
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout:5))
        app.segmentedControls["app-language"].buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        closeSheet(app)
        XCTAssertTrue(app.staticTexts["Taking a rest."].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Camera off"].exists)
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
