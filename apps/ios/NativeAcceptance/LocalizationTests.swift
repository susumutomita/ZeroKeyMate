import XCTest
@testable import ZeroKeyMate

final class LocalizationTests:XCTestCase {
    func testEnglishDefaultIgnoresDeviceLanguageAndOldDevelopmentPreference() {
        let suite="mate-language-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        defaults.set(["ja"],forKey:"AppleLanguages")
        defaults.set("ja",forKey:"mate-language")
        XCTAssertEqual(L10n.language(in:defaults),.english)
        defaults.set("ja",forKey:L10n.preferenceKey)
        XCTAssertEqual(L10n.language(in:defaults),.japanese)
        defaults.set("en",forKey:L10n.preferenceKey)
        XCTAssertEqual(L10n.language(in:defaults),.english)
    }
    func testBothLanguagesIncludeProofRefusalAndEnglishFallback() {
        XCTAssertEqual(L10n.text("Settings",language:.english),"Settings")
        XCTAssertEqual(L10n.text("Settings",language:.japanese),"設定")
        XCTAssertEqual(L10n.text("No proof generated. This service is not allowed.",language:.japanese),"証明は生成していません。このサービスは許可されていません。")
        XCTAssertEqual(L10n.text("No proof generated. This service is not allowed.",language:.english),"No proof generated. This service is not allowed.")
        let disclosedText="A user-authored text that must remain unchanged."
        XCTAssertEqual(L10n.text(disclosedText,language:.japanese),disclosedText)
        XCTAssertEqual(AppLanguage.english.speechLocale,"en-US")
        XCTAssertEqual(AppLanguage.japanese.speechLocale,"ja-JP")
    }
}
