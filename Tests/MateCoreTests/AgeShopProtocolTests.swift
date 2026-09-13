import XCTest
@testable import MateCore

final class AgeShopProtocolTests: XCTestCase {
    private struct Reference: Decodable {
        let connection: AgeShopConnection, key: String, now: UInt64, order: AgeShopOrder
        let materialHex: String, nonceMaterialHex: String
    }
    private func reference() throws -> Reference {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "order", withExtension: "json", subdirectory: "Shop"))
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    }
    private func check(_ order: AgeShopOrder, ref: Reference, now: UInt64? = nil) throws {
        // Independent viem-generated input/output reference; this closure is
        // deliberately not a hash implementation. Native tests use real Keccak.
        try AgeShopProtocol.validate(order, connection: ref.connection, payer: ref.order.payer, key: ref.key, now: now ?? ref.now) { bytes in
            if bytes == Data(ref.key.utf8) { return try CanonicalBytes.hex(ref.order.id, count: 32) }
            if CanonicalBytes.hexString(bytes) == ref.nonceMaterialHex { return try CanonicalBytes.hex(ref.order.paymentNonce, count: 32) }
            if CanonicalBytes.hexString(bytes) == ref.materialHex { return try CanonicalBytes.hex(ref.order.orderHash, count: 32) }
            throw AgeShopError.invalidOrder
        }
    }
    func testOrderAndNonceABIMatchIndependentViemReference() throws {
        let ref = try reference()
        XCTAssertEqual(try CanonicalBytes.hexString(AgeShopProtocol.orderMaterial(ref.order)), ref.materialHex)
        try check(ref.order, ref: ref)
    }
    func testEveryFinancialIdentityAndTimeSubstitutionFails() throws {
        let ref = try reference()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ref.order)) as? [String: Any])
        let changes: [String: Any] = ["productId": "other", "quantity": 2, "amount": "100001", "chainId": 8453,
            "minimumAge": 19, "payer": "0x" + String(repeating: "44", count: 20),
            "recipient": "0x" + String(repeating: "55", count: 20), "token": "0x" + String(repeating: "66", count: 20),
            "ageGate": "0x" + String(repeating: "77", count: 20), "id": "0x" + String(repeating: "88", count: 32),
            "paymentNonce": "0x" + String(repeating: "99", count: 32), "orderHash": "0x" + String(repeating: "aa", count: 32),
            "createdAt": ref.now + 1, "expiresAt": ref.now + 901]
        for (key, value) in changes {
            var changed = original; changed[key] = value
            let order = try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertThrowsError(try check(order, ref: ref), "Accepted changed \(key)")
        }
        XCTAssertThrowsError(try check(ref.order, ref: ref, now: ref.order.expiresAt))
        // A previously saved Base testnet order is never an Arc authorization.
        var baseOrder = original; baseOrder["chainId"] = 84532
        XCTAssertThrowsError(try check(JSONDecoder().decode(AgeShopOrder.self,
            from: JSONSerialization.data(withJSONObject: baseOrder)), ref: ref))
    }
    func testConnectionCannotCarryCredentialsOrSwitchToPlainHTTP() throws {
        let ref = try reference()
        for origin in ["http://shop.example", "https://user:password@shop.example", "https://shop.example/path", "https://shop.example?key=value", "file:///tmp/shop"] {
            XCTAssertThrowsError(try AgeShopConnection(origin: origin, recipient: ref.connection.recipient,
                ageGate: ref.connection.ageGate, ageGateCodeHash: ref.connection.ageGateCodeHash).validate())
        }
    }
}
