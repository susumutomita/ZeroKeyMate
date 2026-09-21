import XCTest
import Foundation
import MateCore
@testable import ZeroKeyMate

// An isolated URLProtocol supplies public RPC failure cases. No network,
// wallet or card is accessed; these tests do not claim live-chain verification.
private final class ShopTestRPC: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "age-rpc.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let bytes: Data
            if let body = request.httpBody { bytes = body }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var collected = Data(), buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count >= 0 else { throw URLError(.cannotDecodeContentData) }
                    if count == 0 { break }; collected.append(contentsOf: buffer.prefix(count))
                }
                bytes = collected
            } else { throw URLError(.badServerResponse) }
            let body = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let parts = request.url!.pathComponents, mode = parts[1], end = UInt64(parts[2])!
            let method = body["method"] as! String
            let result: Any
            if method == "eth_chainId" { result = mode == "wrong-chain" ? "0x14a34" : "0x4cef52" }
            else if method == "eth_blockNumber" { result = "0x65" }
            else if method == "eth_getTransactionReceipt", mode.hasPrefix("receipt-") {
                let from = "0x" + String(repeating:"0",count:24) + String(repeating:"33",count:20)
                let to = "0x" + String(repeating:"0",count:24) + String(repeating:"22",count:20)
                let amount = CanonicalBytes.hexString(Data(repeating:0,count:24) + CanonicalBytes.u64(end))
                let nonce = "0xa7c746b0a7295cade278c2a890146b1329faf251427d574762a7f6a231961000"
                var logs:[[String:Any]] = [["address":AgeShopProtocol.token,
                    "topics":["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",from,to],"data":amount]]
                if mode != "receipt-no-authorization" {
                    logs.append(["address":AgeShopProtocol.token,
                        "topics":["0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5",from,nonce],"data":"0x"])
                }
                result = ["transactionHash":"0x" + String(repeating:"aa",count:32),
                    "blockNumber":"0x64","blockHash":"0x" + String(repeating:"bb",count:32),
                    "status":mode == "receipt-reverted" ? "0x0":"0x1","logs":logs]
            }
            else if method == "eth_getBlockByNumber" {
                result = ["number": mode == "funds-wrong-block" ? "0x65" : "0x64", "hash": "0x" + String(repeating: "bb", count: 32),
                          "timestamp": "0x" + String(mode == "early" ? end - 1 : end + 1, radix: 16)]
            } else if method == "eth_call" {
                let params = body["params"] as! [Any], call = params[0] as! [String: String]
                if mode.hasPrefix("funds-") {
                    guard call["to"] == AgeShopProtocol.token,
                          call["data"] == "0x70a08231" + String(repeating: "0", count: 24) + String(repeating: "11", count: 20),
                          params[1] as? String == "0x64" else { throw URLError(.badServerResponse) }
                    switch mode {
                    case "funds-short": result = "0x186a0"
                    case "funds-large": result = "0x" + String(repeating: "f", count: 64)
                    default:
                        let units: UInt64 = mode == "funds-zero" ? 0 : mode == "funds-low" ? 99999 : 100000
                        result = CanonicalBytes.hexString(Data(repeating: 0, count: 24) + CanonicalBytes.u64(units))
                    }
                } else {
                guard call["to"] == AgeShopProtocol.token, call["data"]?.hasPrefix("0xe94a0102") == true,
                      call["data"]?.count == 138, params[1] as? String == "0x64" else { throw URLError(.badServerResponse) }
                result = mode == "short" ? "0x0" : "0x" + String(repeating: "0", count: 63) + (mode == "used" ? "1" : "0")
                }
            } else { throw URLError(.unsupportedURL) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0","id":1,"result":result]))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class ShopRPCTests: XCTestCase {
    func testEveryCatalogueQuantityCanConfirmItsExactPaymentReceipt() async throws {
        for product in [ShopProduct.lager, .sparklingWater] {
            for quantity in 1...5 {
                let selection = try ShopSelection(product:product,quantity:quantity)
                let order = try completedOrder(selection)
                let hash = try await rpc("receipt-valid",end:selection.amount).confirmShop(order)
                XCTAssertEqual(hash,"0x" + String(repeating:"bb",count:32))
            }
        }
    }
    func testCatalogueReceiptStillRejectsWrongAmountMissingNonceAndReverts() async throws {
        let water = try completedOrder(ShopSelection(product:.sparklingWater,quantity:3))
        for (mode, amount) in [("receipt-valid",UInt64(100_000)),("receipt-no-authorization",150_000),("receipt-reverted",150_000)] {
            do { _ = try await rpc(mode,end:amount).confirmShop(water);XCTFail("Accepted \(mode) / \(amount)") }
            catch {}
        }
        var changed = try JSONSerialization.jsonObject(with:JSONEncoder().encode(water)) as! [String:Any]
        changed["amount"] = "100000"
        let invalid = try JSONDecoder().decode(AgeShopOrder.self,from:JSONSerialization.data(withJSONObject:changed))
        do { _ = try await rpc("receipt-valid",end:100_000).confirmShop(invalid);XCTFail("Accepted a noncanonical catalogue price") }
        catch { XCTAssertEqual(error as? AgeShopError,.invalidOrder) }
    }
    private func completedOrder(_ selection:ShopSelection) throws -> AgeShopOrder {
        var data = try JSONSerialization.jsonObject(with:JSONEncoder().encode(order())) as! [String:Any]
        data["productId"]=selection.product.rawValue;data["quantity"]=selection.quantity
        data["amount"]=String(selection.amount);data["minimumAge"]=selection.product.minimumAge
        data["state"]="complete";data["paymentTransaction"]="0x" + String(repeating:"aa",count:32)
        // This fixture isolates receipt confirmation. Order commitments are
        // checked by AgeShopClient before this boundary and have separate tests.
        return try JSONDecoder().decode(AgeShopOrder.self,from:JSONSerialization.data(withJSONObject:data))
    }
    func testBuyerFundsUseExactSixDecimalTokenBalanceBeforeCardRead() async throws {
        let payer = "0x" + String(repeating: "11", count: 20)
        for (mode, expected) in [("funds-zero", false), ("funds-low", false), ("funds-exact", true), ("funds-large", true)] {
            let funds = try await rpc(mode, end: 1000).shopFunds(payer: payer, blockNumber: 100)
            XCTAssertEqual(funds.sufficient, expected, mode)
            XCTAssertEqual(funds.blockHash, "0x" + String(repeating: "bb", count: 32))
        }
        for mode in ["funds-short", "funds-wrong-block", "wrong-chain"] {
            do { _ = try await rpc(mode, end: 1000).shopFunds(payer: payer, blockNumber: 100); XCTFail("Accepted \(mode)") }
            catch { }
        }
    }
    private func order() throws -> AgeShopOrder {
        let bundle = Bundle(for: Self.self)
        let file = bundle.url(forResource: "shop-order", withExtension: "json")
            ?? bundle.url(forResource: "shop-order", withExtension: "json", subdirectory: "AgeFixtures")
        let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(file))) as! [String: Any]
        var order = reference["order"] as! [String: Any]
        order["paymentValidBefore"] = (order["createdAt"] as! UInt64) + 180
        order["state"] = "payment_expired"
        return try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: order))
    }
    private func rpc(_ mode: String, end: UInt64) -> EthereumRPC {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ShopTestRPC.self]
        return EthereumRPC(url: "https://age-rpc.invalid/\(mode)/\(end)", chainID: AgeShopProtocol.chainID, sessionConfiguration: configuration)
    }
    func testFinalizedUnusedAuthorizationAndFailureCases() async throws {
        let order = try order(), end = try XCTUnwrap(order.paymentValidBefore)
        let client = rpc("unused", end: end)
        let height = try await client.finalizedShopHeight(); XCTAssertEqual(height, 100)
        let hash = try await client.confirmUnusedShop(order, validBefore: end, blockNumber: height)
        XCTAssertEqual(hash, "0x" + String(repeating: "bb", count: 32))
        var lostPost = try JSONSerialization.jsonObject(with: JSONEncoder().encode(order)) as! [String: Any]
        lostPost.removeValue(forKey: "paymentValidBefore"); lostPost["state"] = "age_verified"
        let unreceived = try JSONDecoder().decode(AgeShopOrder.self, from: JSONSerialization.data(withJSONObject: lostPost))
        let lostHash = try await client.confirmUnusedShop(unreceived, validBefore: end, blockNumber: height)
        XCTAssertEqual(lostHash, hash, "A lost POST must be recoverable using the locally saved signed deadline")
        for mode in ["used", "short", "early"] {
            do { _ = try await rpc(mode, end: end).confirmUnusedShop(order, validBefore: end, blockNumber: 100); XCTFail("Accepted \(mode)") }
            catch { }
        }
        do { _ = try await client.confirmUnusedShop(order, validBefore: end - 1, blockNumber: 100); XCTFail("Accepted an earlier unsigned deadline") }
        catch { XCTAssertEqual(error as? AgeShopError, .invalidPayment) }
        do { _ = try await rpc("wrong-chain", end: end).finalizedShopHeight(); XCTFail("Accepted the wrong chain") }
        catch { }
    }
}
