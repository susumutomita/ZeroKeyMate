import XCTest
import MateCore
import MateAgeProof
@testable import ZeroKeyMate

final class ShopFailureRecoveryTests: XCTestCase {
    @MainActor func testProofFailureSurvivesRestartWithoutReturningToPasswordEntry() throws {
        struct Fixture: Decodable { let connection: AgeShopConnection; let key: String; let order: AgeShopOrder }
        let bundle = Bundle(for: Self.self)
        let file = bundle.url(forResource: "shop-order", withExtension: "json")
            ?? bundle.url(forResource: "shop-order", withExtension: "json", subdirectory: "AgeFixtures")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: XCTUnwrap(file)))
        var saved = SavedShopOrder(connection: fixture.connection, key: fixture.key, order: fixture.order)
        saved.ageProofFailure = .nativeConstraints
        let restored = try JSONDecoder().decode(SavedShopOrder.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(ShopCheckout.recoveryPhase(restored, now: fixture.order.createdAt + 1), .proofFailed)
        // An outstanding authorization must take precedence over any failure
        // marker: never claim "nothing paid" after a payment may have escaped.
        saved.paymentHeader = "synthetic-test-authorization"
        XCTAssertEqual(ShopCheckout.recoveryPhase(saved, now: fixture.order.createdAt + 1), .pending)
        saved.paymentHeader = nil
        XCTAssertEqual(ShopCheckout.recoveryPhase(saved, now: fixture.order.expiresAt), .unavailable)
    }

    func testDiagnosticNeverSerializesPrivateUnderlyingErrors() throws {
        let secret = "synthetic-private-certificate-not-for-diagnostics"
        let error = NSError(domain: secret, code: 123, userInfo: [NSLocalizedDescriptionKey: secret])
        let classified = AgeProofFailure.classify(error)
        XCTAssertEqual(classified, .unknown)
        XCTAssertEqual(AgeProofFailure.classify(MateAgeNativeError.rejected(4)), .nativeConstraints)
        XCTAssertEqual(AgeProofFailure.classify(MateAgeNativeError.rejected(8)), .nativeBusy)
        XCTAssertEqual(AgeProofFailure.classify(MateAgeNativeError.rejected(999)), .unknown)
        for failure in AgeProofFailure.allCases {
            let encoded = String(decoding: try JSONEncoder().encode(failure), as: UTF8.self)
            XCTAssertFalse(encoded.contains(secret))
            XCTAssertFalse(failure.explanation.contains(secret))
            XCTAssertNotEqual(L10n.text(failure.explanation, language: .japanese), failure.explanation)
        }
    }

    func testCompletionQuestionsCannotFallThroughToLanguageModel() {
        for text in ["購入完了ですか", "購入は完了しましたか？", "支払いは完了した？", "もう買えた？", "ビールは買ってくれたの？",
                     "年齢の証明は完了しましたか", "Is my purchase complete?", "Did you buy the beer?", "Have you bought my beer yet?",
                     "Is the payment confirmed?", "Check my order"] {
            XCTAssertTrue(ShopOrderQuestion.matches(text), text)
        }
        for text in ["Buy me a beer", "Translate 'is my purchase complete' into Japanese", "購入完了ですかを英語にして", "I bought a beer yesterday"] {
            XCTAssertFalse(ShopOrderQuestion.matches(text), text)
        }
    }

    func testSpokenAnswersDistinguishAgeFromPaymentAndAreLocalized() {
        XCTAssertTrue(ShopCheckout.Phase.paymentApproval.purchaseAnswer.hasPrefix("Not yet."))
        XCTAssertTrue(ShopCheckout.Phase.proofFailed.purchaseAnswer.contains("No payment was sent"))
        XCTAssertFalse(ShopCheckout.Phase.pending.purchaseAnswer.contains("No payment was sent"))
        XCTAssertTrue(ShopCheckout.Phase.complete.purchaseAnswer.hasPrefix("Yes."))
        for phase: ShopCheckout.Phase in [.proofFailed, .verificationFailed, .paymentApproval, .pending, .complete, .card, .expired, .unavailable] {
            XCTAssertNotEqual(L10n.text(phase.purchaseAnswer, language: .japanese), phase.purchaseAnswer)
        }
    }
}
