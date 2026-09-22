import XCTest
import MateCore
import CoreNFC
@testable import ZeroKeyMate

final class ShopProposalTests: XCTestCase {
    func testModelProposalsResolveOnlyExplicitBoundedCatalogueSelections() throws {
        let water = ShopPlan(intent: .purchaseNow, operation: .buyWater, quantity: 3)
        XCTAssertEqual(try ShopPlanner.selection(for: water, input: "Buy me three waters."), try ShopSelection(product: .sparklingWater, quantity: 3))
        // Word boundaries allow "water", not invented SKU data or a model's
        // confident assertion about a different product.
        for input in ["Buy me milk", "Buy beer and water", "Buy water and a Mac mini", "Buy 12 bottles of water", "Buy 1.5 bottles of water", "Translate buy water into Japanese", "I bought water yesterday"] {
            XCTAssertThrowsError(try ShopPlanner.selection(for: water, input: input))
        }
        XCTAssertThrowsError(try ShopPlanner.selection(for: ShopPlan(intent: .purchaseNow, operation: .buyBeer, quantity: 6), input: "Buy six beers"))
        XCTAssertThrowsError(try ShopPlanner.selection(for: ShopPlan(intent: .negated, operation: .buyWater, quantity: 1), input: "Buy water"))
        XCTAssertEqual(try ShopPlanner.selection(for: water, input: "炭酸水を3本買って"), try ShopSelection(product: .sparklingWater, quantity: 3))
    }
    @MainActor func testWaterRecoveryNeverRequestsAPINButTamperedBeerStillCannotSkipProof() throws {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "shop-order", withExtension: "json") ?? bundle.url(forResource: "shop-order", withExtension: "json", subdirectory: "AgeFixtures")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(url))) as? [String: Any])
        let connection = try JSONDecoder().decode(AgeShopConnection.self, from: JSONSerialization.data(withJSONObject: fixture["connection"]!))
        var fields = try XCTUnwrap(fixture["order"] as? [String: Any])
        fields["productId"] = "mate-sparkling-water"; fields["quantity"] = 3; fields["amount"] = "150000"; fields["minimumAge"] = 0; fields["state"] = "payment_ready"
        let water = try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: fields))
        let saved = SavedShopOrder(connection: connection, key: fixture["key"] as! String, order: water)
        XCTAssertTrue(ShopCheckout.ageRequirementSatisfied(water, marker: nil))
        XCTAssertEqual(ShopCheckout.recoveryPhase(saved, now: water.createdAt + 1), .paymentApproval)
        // A server's unchecked minimumAge alone never establishes eligibility.
        fields["productId"] = "mate-lager"; fields["amount"] = "300000"
        let tampered = try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertFalse(ShopCheckout.ageRequirementSatisfied(tampered, marker: nil))
        fields["minimumAge"] = 20; fields["state"] = "age_verified"
        let beer = try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertFalse(ShopCheckout.ageRequirementSatisfied(beer, marker: nil))
    }
    @MainActor func testNFCFailuresKeepActionableReasonsWithoutUnderlyingCardData() {
        let cases: [(NFCReaderError.Code, CardScanError)] = [
            (.readerErrorSecurityViolation, .permissionMissing),
            (.readerSessionInvalidationErrorSystemIsBusy, .busy),
            (.readerSessionInvalidationErrorSessionTimeout, .timedOut),
            (.readerSessionInvalidationErrorUserCanceled, .cancelled)
        ]
        for (code, expected) in cases {
            let system = NSError(domain: NFCErrorDomain, code: code.rawValue,
                                 userInfo: [NSLocalizedDescriptionKey: "synthetic-private-card-data"])
            let classified = MyNumberNFCService.scanFailure(system)
            XCTAssertEqual(classified, expected)
            let explanation = ShopCheckout.explanation(classified)
            XCTAssertFalse(explanation.contains("synthetic-private-card-data"))
            XCTAssertNotEqual(L10n.text(explanation, language: .japanese), explanation)
        }
    }
    func testOrdinaryAcquisitionIdiomsAreNotPurchases() {
        for text in ["Get some rest.", "Can you get to the point?", "Please bring me up to speed.", "I want you to get better soon.", "Could you please fetch the meaning of that word?"] {
            XCTAssertFalse(ShopPlanner.isCurrentPurchaseRequest(text),text)
        }
        for text in ["Get me a beer", "Please bring two waters", "Buy me a Mac mini"] {
            XCTAssertTrue(ShopPlanner.isCurrentPurchaseRequest(text),text)
        }
    }
    func testPastHypotheticalQuotedAndNegatedSpeechCannotProposeShopping() {
        for text in ["I bought a beer yesterday.","If I asked you to buy beer, what would happen?", "Could Mate buy beer someday?", "昨日ビールを買いました。", "ビールは買わないで。"] {
            XCTAssertFalse(ShopPlanner.isCurrentPurchaseRequest(text), text)
        }
        for text in ["Translate 'buy beer' into Japanese.","「ビールを買って」を英語にして。"] {
            XCTAssertTrue(ShopPlanner.isLanguageTask(text), text)
        }
        for text in ["Buy me one beer.","Can you get me a beer, please?", "I would like you to buy a beer for me.", "ビールを1本買って。"] {
            XCTAssertTrue(ShopPlanner.isCurrentPurchaseRequest(text), text)
        }
    }
    @MainActor func testServerAgeStatusCannotSupplyLocalProofEvidence() throws {
        let bundle=Bundle(for:Self.self)
        let file=bundle.url(forResource:"shop-order",withExtension:"json") ?? bundle.url(forResource:"shop-order",withExtension:"json",subdirectory:"AgeFixtures")
        let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:XCTUnwrap(file))) as! [String:Any]
        var malicious=reference["order"] as! [String:Any]
        malicious["state"]="age_verified"
        malicious["locallyProvenOrderHash"]=malicious["orderHash"]
        let order=try JSONDecoder().decode(AgeShopOrder.self,from:JSONSerialization.data(withJSONObject:malicious))
        XCTAssertFalse(ShopCheckout.hasLocalProof(order,marker:nil))
        XCTAssertFalse(ShopCheckout.hasLocalProof(order,marker:"0x"+String(repeating:"ff",count:32)))
        XCTAssertFalse(ShopCheckout.hasLocalProof(order,marker:"malformed"))
        XCTAssertTrue(ShopCheckout.hasLocalProof(order,marker:order.orderHash))
    }
    func testPurchaseInstructionsFollowTheSelectedDisplayLanguage() {
        XCTAssertEqual(L10n.text("Approve the exact payment", language:.english), "Approve the exact payment")
        XCTAssertEqual(L10n.text("Approve the exact payment", language:.japanese), "この支払いを承認してください")
        XCTAssertNotEqual(L10n.text("Your phone is making the proof", language:.japanese), "Your phone is making the proof")
        let template=L10n.text("The signature password was rejected. %lld attempts remain. Mate did not retry.", language:.japanese)
        XCTAssertEqual(String(format:template,Int64(2)), "署名用パスワードが違います。残り2回です。Mateは再試行していません。")
        let timing = L10n.text("Age proof made on this phone · %.1f s", language: .japanese)
        XCTAssertEqual(String(format: timing, locale: Locale(identifier: "ja"), 12.5), "このスマホで年齢証明を作成・12.5秒")
    }
    func testAgeSubmissionDoesNotIncludeLocalPerformanceMeasurements() throws {
        // The local result may grow device diagnostics without expanding the
        // disclosure accepted by the shop client. Synthetic public fields only.
        let measured = MeasuredAgeProof(
            proof: VerifiedAgeProof(proof: "0x" + String(repeating: "11", count: 384),
                                    rootKeyHash: "0x" + String(repeating: "22", count: 32)),
            timing: AgeProofTiming(totalMilliseconds: 12345, nativeMilliseconds: 12000))
        let submitted = try JSONSerialization.jsonObject(with: JSONEncoder().encode(measured.proof)) as! [String: Any]
        XCTAssertEqual(Set(submitted.keys), ["proof", "rootKeyHash"])
    }
    @MainActor func testExpiredCardStepExplainsHowToRecoverInBothLanguages() {
        let message = ShopCheckout.explanation(MyNumberCardError.requestExpired)
        XCTAssertEqual(message, "This order expired. Mate stopped the card step. Start a new order.")
        XCTAssertEqual(L10n.text(message, language: .japanese), "注文の期限が切れたため、カードの処理を停止しました。新しい注文を開始してください。")
    }
    @MainActor func testWalletSDKEncodesTheCompleteLimitedUSDCSigningDomain() throws {
        // Public synthetic message only: no wallet is initialized or accessed.
        let message=["from":"0x"+String(repeating:"11",count:20), "to":"0x"+String(repeating:"22",count:20),
                     "value":"100000", "validAfter":"1789236000", "validBefore":"1789236180", "nonce":"0x"+String(repeating:"33",count:32)]
        let data=try JSONEncoder().encode(WalletService.shopTypedData(authorization:message))
        let payload=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        let domain=try XCTUnwrap(payload["domain"] as? [String:Any])
        XCTAssertEqual(domain["name"] as? String,"USDC")
        XCTAssertEqual(domain["version"] as? String,"2")
        XCTAssertEqual(domain["chainId"] as? Int,5042002)
        XCTAssertEqual(domain["verifyingContract"] as? String,AgeShopProtocol.token)
        XCTAssertEqual(payload["primaryType"] as? String,"TransferWithAuthorization")
        XCTAssertEqual(payload["message"] as? [String:String],message)
        let types=try XCTUnwrap(payload["types"] as? [String:[[String:String]]])
        XCTAssertEqual(types["EIP712Domain"],[
            ["name":"name","type":"string"],["name":"version","type":"string"],
            ["name":"chainId","type":"uint256"],["name":"verifyingContract","type":"address"]])
        XCTAssertEqual(types["TransferWithAuthorization"]?.map{$0["name"]},["from","to","value","validAfter","validBefore","nonce"])
    }
}
