import XCTest
@testable import MateCore

final class PaymentSignatureTests: XCTestCase {
    // viem 2.56.3 independently produced this vector with the public test scalar
    // 1. No existing wallet/key was read; this signature was never broadcast.
    private let payer = "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"
    private let signature = "0x1f11ac53301a48711f6dccfd284ec0a92af7802796732cd057a2885ae7315f91579a61006b575b272e9cae235f5ebf6455ecc4e68517f044455a35143c7d73ab1c"
    private func approval(amount: String = "50000", payer: String? = nil, nonce: String? = nil) throws -> PaymentApproval {
        let service = try PaymentService(resource: "https://api.example.com/data", recipient: "0x" + String(repeating: "22", count: 20), maximumAmount: 100000)
        let wire: [String: Any] = ["x402Version": 2, "resource": ["url": service.resource], "accepts": [[
            "scheme": "exact", "network": AgeShopProtocol.network, "asset": AgeShopProtocol.token,
            "amount": amount, "payTo": service.recipient, "maxTimeoutSeconds": 60,
            "extra": ["name": "USDC", "version": "2"]]]]
        let request = try PaymentRequest.parse(header: JSONSerialization.data(withJSONObject: wire).base64EncodedString(), service: service, now: 1000)
        return try PaymentApproval(request: request, payer: payer ?? self.payer,
            nonce: nonce ?? ("0x" + String(repeating: "33", count: 32)), now: 1001)
    }
    func testViemTypedDataHashAndSignerRecovery() throws {
        let a = try approval()
        XCTAssertEqual(CanonicalBytes.hexString(try PaymentSignatureVerifier.digest(a)), "0x76805d2fcf6cb98aec33e77541a9a42d070d3d6a553e7e89e143105400e5e9cf")
        try PaymentSignatureVerifier().verify(signature, approval: a)
        // Ethereum uses Keccak padding, not NIST SHA3-256 padding.
        XCTAssertEqual(CanonicalBytes.hexString(PaymentSignatureVerifier.hash(Data())), "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    }
    func testWrongPayerAmountNonceAndMalformedSignaturesFail() throws {
        for a in [try approval(amount: "50001"), try approval(payer: "0x" + String(repeating: "11", count: 20)),
                  try approval(nonce: "0x" + String(repeating: "34", count: 32))] {
            XCTAssertThrowsError(try PaymentSignatureVerifier().verify(signature, approval: a))
        }
        let a = try approval()
        for s in ["0x01", "0x" + String(repeating: "00", count: 65),
                  String(signature.dropLast(2)) + "00", String(signature.dropLast(2)) + "1d",
                  "0x" + String(repeating: "ff", count: 64) + "1b"] {
            XCTAssertThrowsError(try PaymentSignatureVerifier().verify(s, approval: a))
        }
    }
}
