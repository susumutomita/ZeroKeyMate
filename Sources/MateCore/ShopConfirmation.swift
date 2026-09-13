import Foundation

/// Bounded observation of an existing payment. The supplied check must be
/// read-only: this runner never authorizes, signs, retries or replaces a payment.
@MainActor public enum ShopConfirmation {
    public static func observe(
        check: () async throws -> Bool,
        wait: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0 * 1_000_000_000) }
    ) async throws -> Bool {
        // Six observations with 50 seconds of backoff plus request timeouts.
        // A missing provider must not leave
        // the screen busy forever or produce an unbounded background poller.
        for seconds: UInt64 in [1, 2, 4, 8, 15, 20] {
            try Task.checkCancellation()
            try await wait(seconds)
            try Task.checkCancellation()
            do {
                if try await check() { return true }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A transient read failure leaves the same order outstanding.
            }
        }
        return false
    }
}
