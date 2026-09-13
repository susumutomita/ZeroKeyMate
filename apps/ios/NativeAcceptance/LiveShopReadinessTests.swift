import XCTest
@testable import ZeroKeyMate

/// Opt-in public network probe. No saved order, wallet, PIN or card is accessed.
final class LiveShopReadinessTests: XCTestCase {
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
