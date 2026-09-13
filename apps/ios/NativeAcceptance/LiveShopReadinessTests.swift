import XCTest
@testable import ZeroKeyMate

/// Explicit physical-phone probes: public catalog reads and separately opted-in
/// saved-order recovery. No probe reads a PIN or card, or signs a payment.
final class LiveShopReadinessTests: XCTestCase {
    /// Runs the app's existing read-only recovery on the phone. The order
    /// capability stays inside its Keychain/client; only a fixed answer leaves.
    @MainActor func testSavedOrderRecoveryFromThePhysicalPhone() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Explicit physical-phone saved-order probe.")
#else
        guard ProcessInfo.processInfo.environment["MATE_SAVED_SHOP_PROBE"] == "1" else {
            throw XCTSkip("Saved-order recovery probe was not explicitly selected.")
        }
        let answer = await ShopCheckout.savedOrderAnswer()
        let allowed = Set([
            ShopCheckout.Phase.complete.purchaseAnswer, ShopCheckout.Phase.pending.purchaseAnswer,
            ShopCheckout.Phase.proofFailed.purchaseAnswer, ShopCheckout.Phase.verificationFailed.purchaseAnswer,
            ShopCheckout.Phase.paymentApproval.purchaseAnswer, ShopCheckout.Phase.expired.purchaseAnswer,
            ShopCheckout.Phase.card.purchaseAnswer, ShopCheckout.Phase.unavailable.purchaseAnswer,
            "I couldn't check the saved order right now. I cannot confirm that the purchase is complete."
        ])
        XCTAssertTrue(allowed.contains(answer))
        let report = ["savedOrderPresent": ShopCheckout.hasSavedOrder(), "answer": allowed.contains(answer) ? answer : "unclassified"] as [String: Any]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "saved-order-fixed-status"; attachment.lifetime = .keepAlways
        add(attachment)
#endif
    }

    func testPublicCatalogFromThePhysicalPhone() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Explicit physical-phone network probe.")
#else
        guard ProcessInfo.processInfo.environment["MATE_PUBLIC_SHOP_PROBE"] == "1" else {
            throw XCTSkip("Public shop network probe was not explicitly selected.")
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://zerokeymate-arc-shop.oyster880.workers.dev/api/catalog")!
        let allowedCodes = Set(["configuration", "age_network", "storage", "capacity", "settlement_network", "settlement", "ready"])
        var samples: [[String: Any]] = []
        for i in 1...3 {
            var sample: [String: Any] = ["sample": i]
            let start = ContinuousClock.now
            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                let http = try XCTUnwrap(response as? HTTPURLResponse)
                sample["http"] = http.statusCode
                if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    sample["available"] = value["checkoutAvailable"] as? Bool
                    if let code = value["availabilityCode"] as? String, allowedCodes.contains(code) {
                        sample["stage"] = code
                    }
                }
                if let edge = http.value(forHTTPHeaderField: "cf-ray")?.split(separator: "-").last,
                   edge.count == 3, edge.allSatisfy({ $0.isASCII && $0.isUppercase }) {
                    sample["edge"] = String(edge)
                }
            } catch {
                sample["networkErrorCode"] = (error as NSError).code
            }
            let elapsed = start.duration(to: .now).components
            sample["milliseconds"] = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
            samples.append(sample)
            if i < 3 { try await Task.sleep(for: .seconds(2)) }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "public-shop-readiness"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(samples.allSatisfy { ($0["available"] as? Bool) == true }, "Inspect the public-only readiness attachment.")
#endif
    }
}
