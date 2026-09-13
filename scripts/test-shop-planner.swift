// Build with the unchanged production ShopPlanner.swift on macOS 26+.
// Canned public sentences only; no model output is an order or payment.
import Foundation
import FoundationModels

@main struct ShopPlannerAcceptance {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("Local shopping model unavailable on this host; classification NOT verified.")
            exit(2)
        }
        let cases: [(String, ShopOperation, Int?)] = [
            ("Buy me one beer.", .buyBeer, 1),
            ("ビールを1本買って。", .buyBeer, 1),
            ("Buy two beers.", .buyBeer, 2),
            ("Please buy a Mac mini on Amazon.", .unsupportedPurchase, nil),
            ("Don't buy beer.", .chat, nil),
            ("Translate 'buy beer' into Japanese.", .chat, nil),
            ("I bought a beer yesterday.", .chat, nil),
            ("Could Mate buy beer someday?", .chat, nil),
            ("Can you get me a beer, please?", .buyBeer, 1),
            ("ビールは買わないで。", .chat, nil),
            ("「ビールを買って」を英語にして。", .chat, nil),
            ("昨日ビールを買いました。", .chat, nil),
            ("I would like you to buy a beer for me.", .buyBeer, 1),
            ("If I asked you to buy beer, what would happen?", .chat, nil)
        ]
        let planner = ShopPlanner()
        var failures = 0
        for (input, expected, count) in cases {
            do {
                let result = try await planner.plan(input)
                let matches = String(describing: result.operation) == String(describing: expected)
                    && (count == nil || result.quantity == count)
                print("\(matches ? "PASS" : "FAIL") | \(input) | \(result.operation) | quantity \(result.quantity)")
                if !matches { failures += 1 }
            } catch {
                print("FAIL | \(input) | local model could not produce a plan")
                failures += 1
            }
        }
        print("Production planner with real host model and language-task guard: \(cases.count - failures)/\(cases.count) passed. No order, key or payment accessed.")
        exit(failures == 0 ? 0 : 1)
    }
}
