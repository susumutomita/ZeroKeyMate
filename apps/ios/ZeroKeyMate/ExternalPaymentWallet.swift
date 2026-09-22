import Foundation
import LocalAuthentication
import MateCore

/// One evaluation owns this context; the cancellation handler may only invalidate
/// it. LAContext explicitly supports invalidating a pending evaluation.
private final class PaymentAuthentication: @unchecked Sendable {
    let context = LAContext()
}

/// The approval UI displays these immutable terms before this adapter can be
/// invoked. Face ID/passcode is an additional owner check, not the quote UI.
struct DevicePaymentApprover: ExternalPaymentApprover {
    func approve(_ approval: PaymentApproval) async throws {
        let authentication = PaymentAuthentication()
        var error: NSError?
        guard authentication.context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw ProductError.unavailable("Owner approval requires your device passcode or Face ID.")
        }
        let host = URL(string: approval.request.service.resource)?.host ?? ""
        guard let units = UInt64(approval.authorization.value) else { throw ExternalPaymentError.invalidAuthorization }
        let amount = String(format: "%.6f", Double(units) / 1_000_000)
        let reason = L10n.format("Approve %@ test USDC for %@", amount, host)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard try await authentication.context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
                throw ProductError.cancelled
            }
            try Task.checkCancellation()
        } onCancel: {
            authentication.context.invalidate()
        }
    }
}

/// This capability is handed only to PaymentApprovalCoordinator, never to the
/// local language model or a web page. It cannot sign arbitrary typed data.
struct PrivyPaymentSigner: ExternalPaymentSigner {
    let wallet: WalletService
    func sign(_ approval: PaymentApproval) async throws -> String {
        try await wallet.signExternalPayment(approval)
    }
}
