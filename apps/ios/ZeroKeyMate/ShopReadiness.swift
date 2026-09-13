import Foundation

@MainActor enum ShopReadiness {
    /// Read-only readiness only. Never reuse this loop for PINs or payments.
    /// Every successful attempt must independently satisfy the full checks.
    static func waitForAvailability(
        check: () async throws -> Bool,
        pause: () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }
    ) async throws -> Bool {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                if try await check() { return true }
            } catch let error as URLError where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code) {
                if attempt == 2 { throw error }
            }
            if attempt < 2 { try await pause() }
        }
        return false
    }
}
