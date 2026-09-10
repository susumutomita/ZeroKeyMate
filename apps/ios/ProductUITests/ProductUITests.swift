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
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout: 15))
        if app.buttons["open-controls"].exists {app.buttons["open-controls"].tap()}
        else {app.buttons["companion-face"].swipeUp()}
        XCTAssertTrue(app.buttons["start-companion"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["start-companion"].isHittable)
        // A preceding failed language test must not change the next test's language.
        app.buttons["open-settings"].tap()
        let language=app.segmentedControls["app-language"]
        XCTAssertTrue(language.waitForExistence(timeout:5))
        if !language.buttons["English"].isSelected {language.buttons["English"].tap()}
        closeSheet(app)
        return app
    }
    private func closeSheet(_ app: XCUIApplication) {
        app.buttons["close-sheet"].tap()
        XCTAssertTrue(app.buttons["close-sheet"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout:5))
        app.buttons["companion-face"].swipeUp()
        XCTAssertTrue(app.buttons["open-conversation"].waitForExistence(timeout:5))
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
        for id in ["start-companion", "rest-button", "open-conversation", "open-settings"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists, id)
            XCTAssertTrue(button.isHittable, id)
            XCTAssertTrue(window.contains(button.frame), "Clipped control: \(id)")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
    }
    func testSetupCanBeDeferredAndResumedWithoutStartingSensors() {
        let app=launch()
        XCTAssertTrue(app.staticTexts["Camera off"].exists)
        app.buttons["open-setup"].tap()
        XCTAssertTrue(app.navigationBars["Set up external requests"].waitForExistence(timeout:10))
        let connection=app.buttons["Configure connection"]
        XCTAssertTrue(connection.waitForExistence(timeout:15))
        connection.tap()
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout:5))
        XCTAssertTrue(app.secureTextFields["One-time pairing code"].exists)
        XCTAssertFalse(app.secureTextFields["Installation pairing token"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.buttons["Do this later"].waitForExistence(timeout:5))
        app.buttons["Do this later"].tap()
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout:5))
        app.buttons["companion-face"].swipeUp()
        XCTAssertTrue(app.staticTexts["Camera off"].waitForExistence(timeout:5))
        app.buttons["open-setup"].tap()
        XCTAssertTrue(app.buttons["Configure connection"].waitForExistence(timeout:10))
        capture("resumed-setup-connection")
    }
    func testTaskExampleIsEditableAndDoesNotAutomaticallySend() {
        let app=launch()
        app.buttons["open-settings"].tap()
        let clear=app.buttons["Clear conversation"]
        for _ in 0..<8 where !clear.isHittable {app.swipeUp()}
        XCTAssertTrue(clear.isHittable);clear.tap()
        closeSheet(app)
        app.buttons["open-conversation"].tap()
        let example=app.buttons["try-agent-request"]
        XCTAssertTrue(example.waitForExistence(timeout:5));example.tap()
        let input=app.textFields["message-input"].exists ? app.textFields["message-input"] : app.textViews["message-input"]
        XCTAssertEqual(input.value as? String,"Translate this into Japanese: The meeting starts at ten.")
        XCTAssertTrue(app.buttons["send-message"].isEnabled)
        XCTAssertFalse(app.buttons["continue-request"].exists)
        capture("editable-agent-request")
    }
    func testSpeakNowRequestsOnlyMicrophoneAndDenialStopsTheSession() {
        let app=launch()
        app.terminate()
        app.resetAuthorizationStatus(for:.microphone)
        app.launch()
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout:15))
        if app.buttons["open-controls"].exists {app.buttons["open-controls"].tap()}
        else {app.buttons["companion-face"].swipeUp()}
        let speak=app.buttons["speak-now"]
        XCTAssertTrue(speak.waitForExistence(timeout:5))
        speak.tap()
        let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let prompt=system.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout:10))
        XCTAssertTrue(prompt.label.lowercased().contains("microphone") || prompt.label.contains("マイク"),prompt.debugDescription)
        let deny=prompt.buttons.matching(NSPredicate(format:"label IN %@",["Don't Allow","Don’t Allow","許可しない"])).firstMatch
        XCTAssertTrue(deny.exists);deny.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5))
        app.alerts.firstMatch.buttons["Close"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout:5))
        // Dismissing the root error presentation can also dismiss its sheet.
        if !app.buttons["rest-button"].exists {
            XCTAssertEqual(app.buttons["companion-face"].value as? String,"Taking a rest.")
            app.buttons["companion-face"].swipeUp()
        }
        XCTAssertTrue(app.staticTexts["camera-status"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["camera-status"].label,"Camera off")
        app.buttons["rest-button"].tap()
        XCTAssertEqual(app.buttons["companion-face"].value as? String,"Taking a rest.")
    }
    func testFaceHasNoVisibleTextOrToolbar() {
        let app=launch()
        app.buttons["close-sheet"].tap()
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["start-companion"].exists)
        XCTAssertFalse(app.buttons["open-settings"].exists)
        XCTAssertEqual(app.buttons["companion-face"].value as? String,"Taking a rest.")
        XCTAssertEqual(app.staticTexts.count,0)
        capture("face-only-home")
    }
    func testLongPressFaceReachesLanguageWithoutStartingSensors() {
        let app=launch()
        app.buttons["close-sheet"].tap()
        XCTAssertTrue(app.buttons["close-sheet"].waitForNonExistence(timeout:5))
        app.buttons["companion-face"].press(forDuration:0.8)
        let settings=app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout:5))
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        let language=app.segmentedControls["app-language"]
        XCTAssertTrue(language.waitForExistence(timeout:5))
        XCTAssertTrue(language.isHittable)
        capture("tap-to-language-settings")
        language.buttons["日本語"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout:5))
        language.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
    }
    func testOneTapOnRestingFaceRequestsCamera() {
        continueAfterFailure=false
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.terminate()
        app.resetAuthorizationStatus(for:.camera)
        app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US","-mate-companion-introduced","YES","-mate-companion-language","en"]
        app.launch()
        let face=app.buttons["companion-face"]
        XCTAssertTrue(face.waitForExistence(timeout:15))
        XCTAssertEqual(face.value as? String,"Taking a rest.")
        face.tap()
        let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        XCTAssertTrue(system.alerts.firstMatch.waitForExistence(timeout:10),"One tap must enter camera permission, not a controls menu")
        let prompt=system.alerts.firstMatch
        XCTAssertTrue(prompt.label.lowercased().contains("camera") || prompt.label.contains("カメラ"),prompt.debugDescription)
        capture("one-tap-camera-consent")
        // Denial is deliberate; this verifies the start path without capturing frames.
        let deny=prompt.buttons.matching(NSPredicate(format:"label IN %@",["Don't Allow","Don’t Allow","許可しない"])).firstMatch
        XCTAssertTrue(deny.exists)
        deny.tap()
        app.terminate()
    }
    func testWelcomeExplainsTheSessionWithoutStartingSensors() {
        let app=launch()
        XCTAssertTrue(app.staticTexts["Camera off"].exists)
        app.buttons["open-welcome"].tap()
        XCTAssertTrue(app.navigationBars["Welcome to Mate"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["start-companion"].isHittable)
        XCTAssertTrue(app.buttons["open-controls"].isHittable)
        capture("00-companion-welcome")
        app.buttons["open-controls"].tap()
        XCTAssertTrue(app.staticTexts["Camera off"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Taking a rest."].exists)
    }
    func testPortraitHomeDoesNotStartSensorsAndControlsRemainAccessible() throws {
        let app = launch()
        assertVisibleControls(app)
        XCTAssertTrue(app.staticTexts["Camera off"].exists)
        capture("01-home-portrait")
        try app.performAccessibilityAudit(for: [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription])
        app.buttons["rest-button"].tap()
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout:3))
        XCTAssertEqual(app.buttons["companion-face"].value as? String,"Taking a rest.")
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
        app.buttons["open-settings"].tap()
        tapPadding(app.buttons["open-activity"])
        XCTAssertTrue(app.staticTexts["No executions yet."].waitForExistence(timeout: 5))
        capture("05-activity-empty")
    }
    func testLocalProofPreflightDoesNotPretendToGenerateProof() {
        let app = launch()
        app.buttons["open-settings"].tap()
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
        app.buttons["open-settings"].tap()
        tapPadding(app.buttons["open-local-proof"])
        let generate = app.buttons["generate-local-proof"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: generate)
        waitForExpectations(timeout: 5)
        generate.tap()
        XCTAssertTrue(app.descendants(matching:.any)["local-proof-ready"].waitForExistence(timeout:120))
        func fullyVisible(_ element:XCUIElement) -> Bool {
            element.exists && element.isHittable &&
                element.frame.minY > app.navigationBars["Local ZK"].frame.maxY &&
                element.frame.maxY < app.buttons["generate-local-proof"].frame.minY
        }
        func scrollDown() {
            // Small drags with a pause avoid flinging past lazily rendered Form rows.
            app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.7))
                .press(forDuration:0.1,
                    thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45)),
                    withVelocity:.slow,thenHoldForDuration:0.2)
        }
        let original=app.staticTexts["Original proof accepted"]
        let modified=app.staticTexts["Modified proof rejected"]
        for _ in 0..<12 {
            if fullyVisible(original) && fullyVisible(modified) {break}
            scrollDown()
        }
        XCTAssertTrue(fullyVisible(original))
        XCTAssertTrue(fullyVisible(modified))
        capture("09-native-proof-verified")
        let prepare=app.buttons["Prepare proof file for sharing"]
        for _ in 0..<12 {
            if fullyVisible(prepare) {break}
            scrollDown()
        }
        XCTAssertTrue(fullyVisible(prepare))
        prepare.tap()
        XCTAssertTrue(app.buttons["Share proof file"].waitForExistence(timeout:5))
        capture("09-native-proof-ready-to-share")
#else
        throw XCTSkip("This source-only build explicitly has no native prover. Run the native acceptance workflow.")
#endif
    }
    func testNativeLocalProofMemoryFootprint() throws {
#if MATE_NATIVE_PROOFS
        let app = launch()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
            // A fresh app process per iteration; OS/file caches may remain warm.
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout: 15))
            app.buttons["companion-face"].swipeUp()
            app.buttons["open-settings"].tap()
            tapPadding(app.buttons["open-local-proof"])
            let generate = app.buttons["generate-local-proof"]
            XCTAssertTrue(generate.waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["local-proof-ready"].exists)
            startMeasuring()
            generate.tap()
            XCTAssertTrue(app.descendants(matching: .any)["local-proof-ready"].waitForExistence(timeout: 120))
            stopMeasuring()
        }
#else
        throw XCTSkip("Native proof memory requires the real bundled prover.")
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
        app.buttons["open-settings"].tap()
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
        XCTAssertTrue(app.buttons["companion-face"].waitForExistence(timeout:15))
        if app.buttons["open-controls"].exists {app.buttons["open-controls"].tap()}
        else{app.buttons["companion-face"].swipeUp()}
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
        app.buttons["close-sheet"].tap()
        XCTAssertTrue(app.buttons["close-sheet"].waitForNonExistence(timeout:5))
        XCUIDevice.shared.orientation = .landscapeLeft
        let predicate = NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }
        expectation(for: predicate, evaluatedWith: nil)
        waitForExpectations(timeout: 8)
        let face=app.buttons["companion-face"]
        XCTAssertTrue(face.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(face.frame))
        XCTAssertEqual(app.staticTexts.count,0)
        capture("06-face-landscape")
        face.swipeUp()
        XCTAssertTrue(app.buttons["start-companion"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["start-companion"].isHittable)
    }
}
