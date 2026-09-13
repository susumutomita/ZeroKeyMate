import XCTest
@testable import MateCore

final class AgeShopReceiptTests: XCTestCase {
    private func order() throws -> AgeShopOrder {
        struct Reference: Decodable { let order: AgeShopOrder }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "order", withExtension: "json", subdirectory: "Shop"))
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url)).order
    }
    func testReceiptRequiresMatchingTokenPayerRecipientAmountAndNonce() throws {
        let order = try order()
        func topic(_ address: String) -> String { "0x" + String(repeating: "0", count: 24) + address.dropFirst(2).lowercased() }
        let transfer = AgeShopReceipt.Log(address: order.token, topics: [
            "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
            topic(order.payer), topic(order.recipient)], data: "0x" + String(repeating: "0", count: 59) + "186a0")
        let used = AgeShopReceipt.Log(address: order.token, topics: [
            "0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5",
            topic(order.payer), order.paymentNonce], data: "0x")
        try AgeShopReceipt.validate(order: order, logs: [transfer, used])
        for index in 0..<2 {
            let logs = [transfer, used]
            XCTAssertThrowsError(try AgeShopReceipt.validate(order: order, logs: [logs[index]]))
            var replaced = logs
            replaced[index] = .init(address: "0x" + String(repeating: "44", count: 20), topics: logs[index].topics, data: logs[index].data)
            XCTAssertThrowsError(try AgeShopReceipt.validate(order: order, logs: replaced))
            for field in logs[index].topics.indices {
                var topics = logs[index].topics; topics[field] = "0x" + String(repeating: "99", count: 32)
                replaced = logs; replaced[index] = .init(address: logs[index].address, topics: topics, data: logs[index].data)
                XCTAssertThrowsError(try AgeShopReceipt.validate(order: order, logs: replaced))
            }
            replaced = logs; replaced[index] = .init(address: logs[index].address, topics: logs[index].topics, data: "0x01")
            XCTAssertThrowsError(try AgeShopReceipt.validate(order: order, logs: replaced))
        }
    }
}
