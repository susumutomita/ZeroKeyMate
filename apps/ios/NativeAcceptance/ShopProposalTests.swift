import XCTest
import MateCore
@testable import ZeroKeyMate

final class ShopProposalTests: XCTestCase {
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
        let template=L10n.text("The signature PIN was rejected. %lld attempts remain. Mate did not retry.", language:.japanese)
        XCTAssertEqual(String(format:template,Int64(2)), "署名用暗証番号が違います。残り2回です。Mateは再試行していません。")
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
        XCTAssertEqual(domain["chainId"] as? Int,84532)
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
