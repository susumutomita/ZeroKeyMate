import Foundation
import MateCore
import MateAgeProof

private final class ShopRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct ShopPaymentRequirements: Codable, Equatable, Sendable {
    let scheme: String, network: String, amount: String, asset: String, payTo: String
    let maxTimeoutSeconds: Int
    let extra: Extra
    struct Extra: Codable, Equatable, Sendable { let name: String, version: String }
    func validate(order: AgeShopOrder) throws {
        guard scheme == "exact", network == AgeShopProtocol.network, amount == AgeShopProtocol.amount,
              asset.lowercased() == AgeShopProtocol.token, payTo.lowercased() == order.recipient.lowercased(),
              maxTimeoutSeconds == 300, extra.name == "USDC", extra.version == "2" else { throw AgeShopError.invalidPayment }
    }
}

/// The local model never gets this client, the order capability or a raw URL.
/// Every response is bounded and every order is recomputed locally before use.
actor AgeShopClient {
    private let connection: AgeShopConnection
    private let session: URLSession
    private let origin: URL
    init(connection: AgeShopConnection) throws {
        origin = try connection.validate(); self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: ShopRedirectPolicy(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    func ready() async throws -> Bool {
        let response = try await request(["api", "catalog"])
        struct Catalog: Decodable { let checkoutAvailable: Bool, chainId: UInt64, testnet: Bool, shipsPhysicalGoods: Bool }
        let catalog = try JSONDecoder().decode(Catalog.self, from: response.data)
        return response.code == 200 && catalog.checkoutAvailable && catalog.chainId == AgeShopProtocol.chainID
            && catalog.testnet && !catalog.shipsPhysicalGoods
    }
    func create(payer: String, key: String) async throws -> AgeShopOrder {
        let data = try JSONSerialization.data(withJSONObject: ["productId": "mate-lager", "quantity": 1, "payer": payer])
        let result = try await request(["api", "orders"], method: "POST", key: key, body: data)
        guard result.code == 201 else { throw ProductError.unavailable("The shop cannot accept this order yet. Nothing was paid.") }
        // The idempotent creation response may be an older order after restart.
        // Keep it for recovery; expiry still prevents a new proof or payment.
        return try decodeOrder(result.data, payer: payer, key: key, allowExpired: true)
    }
    func status(order: AgeShopOrder, key: String) async throws -> AgeShopOrder {
        try validate(order, key: key, allowExpired: true)
        let result = try await request(["api", "orders", order.id], key: key)
        guard result.code == 200 else { throw ProductError.unavailable("The original order cannot be checked yet. Keep this order.") }
        return try decodeOrder(result.data, payer: order.payer, key: key, allowExpired: true, expectedHash: order.orderHash)
    }
    func verifyAge(order: AgeShopOrder, key: String, proof: VerifiedAgeProof) async throws -> AgeShopOrder {
        try validate(order, key: key)
        let result = try await request(["api", "orders", order.id, "age"], method: "POST", key: key,
                                       body: JSONEncoder().encode(proof))
        guard result.code == 200 else { throw ProductError.unavailable("The shop could not verify the age proof. Nothing was paid.") }
        let next = try decodeOrder(result.data, payer: order.payer, key: key, expectedHash: order.orderHash)
        guard next.state == .ageVerified else { throw ProductError.invalidResponse }
        return next
    }
    func paymentChallenge(order: AgeShopOrder, key: String) async throws -> ShopPaymentRequirements {
        try validate(order, key: key)
        let result = try await request(["api", "orders", order.id, "pay"], method: "POST", key: key)
        struct Challenge: Decodable { let x402Version: Int, accepts: [ShopPaymentRequirements] }
        guard result.code == 402, let header = result.paymentRequired, header.utf8.count <= 16384,
              let data = Data(base64Encoded: header) else { throw ProductError.invalidResponse }
        let challenge = try JSONDecoder().decode(Challenge.self, from: data)
        guard challenge.x402Version == 2, challenge.accepts.count == 1 else { throw AgeShopError.invalidPayment }
        let requirement = challenge.accepts[0]; try requirement.validate(order: order)
        return requirement
    }
    func pay(order: AgeShopOrder, key: String, header: String) async throws -> AgeShopOrder {
        try validate(order, key: key)
        guard header.utf8.count <= 16384 else { throw AgeShopError.invalidPayment }
        let result = try await request(["api", "orders", order.id, "pay"], method: "POST", key: key, payment: header)
        guard result.code == 200 || result.code == 202 else {
            throw ProductError.unavailable("The payment result is not confirmed. Check the original order before trying anything else.")
        }
        return try decodeOrder(result.data, payer: order.payer, key: key, allowExpired: true, expectedHash: order.orderHash)
    }

    private func validate(_ order: AgeShopOrder, key: String, allowExpired: Bool = false) throws {
        try AgeShopProtocol.validate(order, connection: connection, payer: order.payer, key: key,
            now: UInt64(Date().timeIntervalSince1970), allowExpired: allowExpired, keccak: MateAgeNative.keccak256)
    }
    private func decodeOrder(_ data: Data, payer: String, key: String, allowExpired: Bool = false, expectedHash: String? = nil) throws -> AgeShopOrder {
        struct Envelope: Decodable { let order: AgeShopOrder }
        let order = try JSONDecoder().decode(Envelope.self, from: data).order
        if let expectedHash, order.orderHash.lowercased() != expectedHash.lowercased() { throw AgeShopError.invalidOrder }
        try AgeShopProtocol.validate(order, connection: connection, payer: payer, key: key,
            now: UInt64(Date().timeIntervalSince1970), allowExpired: allowExpired, keccak: MateAgeNative.keccak256)
        return order
    }
    private struct Response { let code: Int, data: Data, paymentRequired: String? }
    private func request(_ path: [String], method: String = "GET", key: String? = nil,
                         body: Data? = nil, payment: String? = nil) async throws -> Response {
        try Task.checkCancellation()
        var url = origin
        for component in path { url.appendPathComponent(component) }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue(key, forHTTPHeaderField: "X-Order-Key") }
        if let payment { request.setValue(payment, forHTTPHeaderField: "PAYMENT-SIGNATURE") }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.url?.host == origin.host,
              !(300...399).contains(http.statusCode), response.expectedContentLength <= 65536 else { throw ProductError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65536 else { throw ProductError.invalidResponse }; data.append(byte)
        }
        return Response(code: http.statusCode, data: data, paymentRequired: http.value(forHTTPHeaderField: "PAYMENT-REQUIRED"))
    }
}
