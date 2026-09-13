import Foundation

/// Public receipt evidence only; never a substitute for canonical block and
/// confirmation checks. The client obtains matching receipts from two RPCs.
public enum AgeShopReceipt {
    public struct Log: Sendable {
        public let address: String, topics: [String], data: String
        public init(address: String, topics: [String], data: String) {
            self.address = address; self.topics = topics; self.data = data
        }
    }
    public static func validate(order: AgeShopOrder, logs: [Log]) throws {
        guard order.chainId == AgeShopProtocol.chainID, order.token.lowercased() == AgeShopProtocol.token,
              order.amount == AgeShopProtocol.amount else { throw AgeShopError.invalidPayment }
        let from = try CanonicalBytes.hexString(Data(repeating: 0, count: 12) + CanonicalBytes.hex(order.payer, count: 20))
        let to = try CanonicalBytes.hexString(Data(repeating: 0, count: 12) + CanonicalBytes.hex(order.recipient, count: 20))
        let amount = CanonicalBytes.hexString(Data(repeating: 0, count: 24) + CanonicalBytes.u64(100000))
        let transfer = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
        let used = "0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5"
        let own = logs.filter { $0.address.lowercased() == AgeShopProtocol.token }
        guard own.contains(where: { $0.topics.map { $0.lowercased() } == [transfer, from, to] && $0.data.lowercased() == amount }),
              own.contains(where: { $0.topics.map { $0.lowercased() } == [used, from, order.paymentNonce.lowercased()] && $0.data == "0x" }) else {
            throw AgeShopError.invalidPayment
        }
    }
}
