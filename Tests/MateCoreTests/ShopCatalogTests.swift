import XCTest
@testable import MateCore

final class ShopCatalogTests: XCTestCase {
    func testBoundedQuantitiesAndPricesCannotBeOverriddenByDecoding() throws {
        XCTAssertEqual(try ShopSelection(product: .sparklingWater, quantity: 3).amount, 150_000)
        XCTAssertEqual(try ShopSelection(product: .lager, quantity: 5).amount, 500_000)
        for quantity in [Int.min, -1, 0, 6, Int.max] {
            XCTAssertThrowsError(try ShopSelection(product: .lager, quantity: quantity))
            let data = Data("{\"product\":\"mate-lager\",\"quantity\":\(quantity)}".utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(ShopSelection.self, from: data))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ShopSelection.self, from: Data(#"{"product":"invented","quantity":1}"#.utf8)))
    }

    private func order(_ changes: [String: Any]) throws -> AgeShopOrder {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "order", withExtension: "json", subdirectory: "Shop"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var value = try XCTUnwrap(fixture["order"] as? [String: Any])
        value.merge(changes) { _, next in next }
        return try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testMinimumAgeIsDerivedFromTrustedProductAndTotalIsRecomputed() throws {
        let water = try order(["productId": "mate-sparkling-water", "minimumAge": 0, "quantity": 3, "amount": "150000", "state": "payment_ready"])
        XCTAssertFalse(try ShopSelection(order: water).requiresAgeProof)
        XCTAssertTrue(try ShopSelection(order: order([:])).requiresAgeProof)
        for changes: [String: Any] in [["minimumAge": 0], ["amount": "1"], ["quantity": 2], ["productId": "unknown"],
                                      ["productId": "mate-sparkling-water", "amount": "50000", "minimumAge": 20]] {
            XCTAssertThrowsError(try ShopSelection(order: order(changes)))
            XCTAssertThrowsError(try AgeShopProtocol.orderMaterial(order(changes)))
        }
    }

    func testReceiptMustMatchQuantityAndTotalNotLegacyBeerPrice() throws {
        let order = try order(["quantity": 3, "amount": "300000"])
        let from = "0x" + String(repeating: "0", count: 24) + order.payer.dropFirst(2)
        let to = "0x" + String(repeating: "0", count: 24) + order.recipient.dropFirst(2)
        func logs(_ amount: UInt64) -> [AgeShopReceipt.Log] {
            [.init(address: order.token, topics: ["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", from, to], data: CanonicalBytes.hexString(Data(repeating: 0, count: 24) + CanonicalBytes.u64(amount))),
             .init(address: order.token, topics: ["0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5", from, order.paymentNonce], data: "0x")]
        }
        XCTAssertNoThrow(try AgeShopReceipt.validate(order: order, logs: logs(300_000)))
        XCTAssertThrowsError(try AgeShopReceipt.validate(order: order, logs: logs(100_000)))
    }
}
