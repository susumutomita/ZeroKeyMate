import XCTest
@testable import MateCore

private actor ApprovalJournalFixture: PaymentApprovalJournal {
    enum Write: String, CaseIterable { case approval, signing, completion, cancellation, reservation }
    private var state: PaymentJournalState
    private let fail: Write?
    init(state: PaymentJournalState = .init(), fail: Write? = nil) { self.state = state; self.fail = fail }
    private func write(_ step: Write, _ change: (inout PaymentJournalState) throws -> Void) throws {
        var next = state; try change(&next)
        if fail == step { throw URLError(.cannotWriteToFile) }
        // Round-trip the actual persisted representation, not a second state machine.
        state = try JSONDecoder().decode(PaymentJournalState.self, from: JSONEncoder().encode(next))
    }
    func snapshot() -> PaymentJournalState { state }
    func load() throws -> PendingPayment? { try state.pending() }
    func reserve(_ p: PendingPayment) throws { try write(.reservation) { try $0.reserve(p) } }
    func beginApproval(_ a: PaymentApproval) throws { try write(.approval) { try $0.beginApproval(a) } }
    func beginSigning(_ a: PaymentApproval) throws { try write(.signing) { try $0.beginSigning(a) } }
    func finishSigning(_ p: PendingPayment, approval a: PaymentApproval) throws { try write(.completion) { try $0.finishSigning(p, approval: a) } }
    func cancelApproval(_ a: PaymentApproval) throws { try write(.cancellation) { try $0.cancelApproval(a) } }
}
private actor ApprovalLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if !opened { await withCheckedContinuation { waiters.append($0) } } }
    func open() { opened = true; let all = waiters; waiters = []; for waiter in all { waiter.resume() } }
}
private final class ApprovalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 1001
    func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: UInt64) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
private final class ApprovalCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    func add(_ call: String) { lock.lock(); defer { lock.unlock() }; calls.append(call) }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return calls }
}
private struct ApproverFixture: ExternalPaymentApprover {
    let run: @Sendable (PaymentApproval) async throws -> Void
    func approve(_ a: PaymentApproval) async throws { try await run(a) }
}
private struct SignerFixture: ExternalPaymentSigner {
    let run: @Sendable (PaymentApproval) async throws -> String
    func sign(_ a: PaymentApproval) async throws -> String { try await run(a) }
}
private struct VerifierFixture: ExternalPaymentSignatureVerifier {
    let run: @Sendable (String, PaymentApproval) throws -> Void
    func verify(_ s: String, approval a: PaymentApproval) throws { try run(s, a) }
}

final class PaymentApprovalTests: XCTestCase {
    private let signature = "0x" + String(repeating: "44", count: 65) // Never broadcast; no wallet is used.
    private func terms() throws -> PaymentApproval {
        let service = try PaymentService(resource: "https://api.example.com/data", recipient: "0x" + String(repeating: "22", count: 20), maximumAmount: 100_000)
        let wire: [String: Any] = ["x402Version": 2, "resource": ["url": service.resource], "accepts": [[
            "scheme": "exact", "network": AgeShopProtocol.network, "amount": "50000", "asset": AgeShopProtocol.token,
            "payTo": service.recipient, "maxTimeoutSeconds": 60, "extra": ["name": "USDC", "version": "2"]]]]
        let request = try PaymentRequest.parse(header: JSONSerialization.data(withJSONObject: wire).base64EncodedString(), service: service, now: 1000)
        return try PaymentApproval(request: request, payer: "0x" + String(repeating: "11", count: 20), nonce: "0x" + String(repeating: "33", count: 32), now: 1001)
    }
    private func pending(_ a: PaymentApproval) throws -> PendingPayment {
        try PendingPayment(request: a.request, authorization: a.authorization, signature: signature, now: a.createdAt)
    }
    private func fixtures(_ calls: ApprovalCalls) -> (ApproverFixture, SignerFixture, VerifierFixture) {
        let signature = self.signature
        return (ApproverFixture { _ in calls.add("approve") },
                SignerFixture { _ in calls.add("sign"); return signature },
                VerifierFixture { _, _ in calls.add("verify") })
    }
    func testApprovalSignsAndPersistsOnlyTheOriginalTerms() async throws {
        let a = try terms(), journal = ApprovalJournalFixture(), calls = ApprovalCalls()
        let coordinator = PaymentApprovalCoordinator(journal: journal, now: { 1001 })
        let p = try await coordinator.approve(a, with: ApproverFixture { received in
            XCTAssertEqual(received, a)
            let state = await journal.snapshot(); XCTAssertEqual(state.entry, .approving(a))
            calls.add("approve")
        }, signer: SignerFixture { received in
            XCTAssertEqual(received, a)
            let state = await journal.snapshot(); XCTAssertEqual(state.entry, .signing(a))
            calls.add("sign"); return "0x" + String(repeating: "44", count: 65)
        }, verifier: VerifierFixture { s, received in
            XCTAssertEqual(received, a); XCTAssertEqual(s.count, 132); calls.add("verify")
        })
        let saved = try await journal.load(), sequence = calls.all()
        XCTAssertEqual(saved, p); XCTAssertEqual(p, try pending(a)); XCTAssertEqual(sequence, ["approve", "sign", "verify"])
    }
    func testExistingOrRestartedEntriesBlockBeforePrompting() async throws {
        let a = try terms(), p = try pending(a)
        for entry in [PaymentJournalState.Entry.approving(a), .signing(a), .signed(p)] {
            var state = PaymentJournalState(); try state.beginApproval(a)
            if entry != .approving(a) { try state.beginSigning(a) }
            if entry == .signed(p) { try state.finishSigning(p, approval: a) }
            let restored = try JSONDecoder().decode(PaymentJournalState.self, from: JSONEncoder().encode(state))
            let journal = ApprovalJournalFixture(state: restored), calls = ApprovalCalls(), f = fixtures(calls)
            do { _ = try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(a, with: f.0, signer: f.1, verifier: f.2); XCTFail("Restart bypassed entry") }
            catch { XCTAssertEqual(error as? ExternalPaymentError, .unresolvedPayment) }
            let sequence = calls.all(), saved = await journal.snapshot()
            XCTAssertTrue(sequence.isEmpty); XCTAssertEqual(saved.entry, entry)
        }
    }
    func testConcurrentCoordinatorsCannotPromptOrSignTwice() async throws {
        let a = try terms(), journal = ApprovalJournalFixture(), calls = ApprovalCalls(), entered = ApprovalLatch(), release = ApprovalLatch()
        let f = fixtures(calls), first = PaymentApprovalCoordinator(journal: journal, now: { 1001 })
        let task = Task { try await first.approve(a, with: ApproverFixture { _ in
            calls.add("approve"); await entered.open(); await release.wait()
        }, signer: f.1, verifier: f.2) }
        await entered.wait()
        do { _ = try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(a, with: f.0, signer: f.1, verifier: f.2); XCTFail("Duplicate prompt") }
        catch { XCTAssertEqual(error as? ExternalPaymentError, .unresolvedPayment) }
        do { try await journal.reserve(pending(a)); XCTFail("Legacy submit bypassed approval") } catch {}
        await release.open(); _ = try await task.value
        let sequence = calls.all(); XCTAssertEqual(sequence, ["approve", "sign", "verify"])
    }
    func testDeniedOrExpiredApprovalReleasesOnlyUnsignedReservation() async throws {
        for expired in [false, true] {
            let journal = ApprovalJournalFixture(), calls = ApprovalCalls(), clock = ApprovalClock(), f = fixtures(calls)
            let a = try terms(), coordinator = PaymentApprovalCoordinator(journal: journal, now: { clock.read() })
            do { _ = try await coordinator.approve(a, with: ApproverFixture { _ in
                calls.add("approve")
                if expired { clock.set(1060) } else { throw CancellationError() }
            }, signer: f.1, verifier: f.2); XCTFail("Approval should not sign") } catch {}
            let state = await journal.snapshot(), sequence = calls.all()
            XCTAssertNil(state.entry); XCTAssertEqual(sequence, ["approve"])
            clock.set(1001)
            _ = try await coordinator.approve(terms(), with: f.0, signer: f.1, verifier: f.2)
        }
    }
    func testCancellationDuringApprovalNeverCallsSigner() async throws {
        let journal = ApprovalJournalFixture(), entered = ApprovalLatch(), release = ApprovalLatch(), calls = ApprovalCalls(), f = fixtures(calls), a = try terms()
        let task = Task { try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(a, with: ApproverFixture { _ in
            calls.add("approve"); await entered.open(); await release.wait()
        }, signer: f.1, verifier: f.2) }
        await entered.wait(); task.cancel(); await release.open()
        do { _ = try await task.value; XCTFail("Cancelled approval completed") } catch { XCTAssertTrue(error is CancellationError) }
        let state = await journal.snapshot(), sequence = calls.all()
        XCTAssertNil(state.entry); XCTAssertEqual(sequence, ["approve"])
    }
    func testCancellationDuringSigningPreservesReturnedSignature() async throws {
        let journal = ApprovalJournalFixture(), entered = ApprovalLatch(), release = ApprovalLatch(), calls = ApprovalCalls(), f = fixtures(calls), a = try terms(), s = signature
        let task = Task { try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(a, with: f.0, signer: SignerFixture { _ in
            calls.add("sign"); await entered.open(); await release.wait(); return s
        }, verifier: VerifierFixture { _, _ in
            try Task.checkCancellation() // Must run even when the calling task was canceled.
            calls.add("verify")
        }) }
        await entered.wait(); task.cancel(); await release.open()
        do { _ = try await task.value; XCTFail("Cancellation was ignored") } catch { XCTAssertTrue(error is CancellationError) }
        let saved = try await journal.load(); XCTAssertEqual(saved, try pending(a))
    }
    func testSignerOrVerifierFailureKeepsDurableUncertainty() async throws {
        for stage in ["sign", "verify", "malformed"] {
            let journal = ApprovalJournalFixture(), a = try terms(), calls = ApprovalCalls(), f = fixtures(calls), s = signature
            do { _ = try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(a, with: f.0, signer: SignerFixture { _ in
                if stage == "sign" { throw URLError(.timedOut) }
                return stage == "malformed" ? "0x01" : s
            }, verifier: VerifierFixture { _, _ in throw ExternalPaymentError.invalidAuthorization }); XCTFail("Accepted failed provider") } catch {}
            let saved = await journal.snapshot(); XCTAssertEqual(saved.entry, .signing(a))
            XCTAssertThrowsError(try saved.pending())
            var staleCleanup = saved; XCTAssertThrowsError(try staleCleanup.cancelApproval(a))
        }
    }
    func testExpiredLateSignatureIsRetainedButCannotBeSubmitted() async throws {
        let journal = ApprovalJournalFixture(), clock = ApprovalClock(), calls = ApprovalCalls(), f = fixtures(calls), a = try terms(), s = signature
        let p = try await PaymentApprovalCoordinator(journal: journal, now: { clock.read() }).approve(a, with: f.0, signer: SignerFixture { _ in clock.set(2000); return s }, verifier: f.2)
        XCTAssertThrowsError(try p.header(now: clock.read()))
        let saved = try await journal.load(); XCTAssertEqual(saved, p); XCTAssertEqual(p.authorization, a.authorization)
    }
    func testPersistenceFailureDoesNotProceedToNextCapability() async throws {
        for step in [ApprovalJournalFixture.Write.approval, .signing, .completion, .cancellation] {
            let journal = ApprovalJournalFixture(fail: step), calls = ApprovalCalls(), f = fixtures(calls), a = try terms()
            let approver = ApproverFixture { _ in calls.add("approve"); if step == .cancellation { throw CancellationError() } }
            do { _ = try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(a, with: approver, signer: f.1, verifier: f.2); XCTFail("Ignored storage failure") } catch {}
            let state = await journal.snapshot(), sequence = calls.all()
            switch step {
            case .approval: XCTAssertNil(state.entry); XCTAssertTrue(sequence.isEmpty)
            case .signing, .cancellation: XCTAssertEqual(state.entry, .approving(a)); XCTAssertEqual(sequence, ["approve"])
            case .completion: XCTAssertEqual(state.entry, .signing(a)); XCTAssertEqual(sequence, ["approve", "sign", "verify"])
            case .reservation: XCTFail("Unused test case")
            }
        }
    }
    func testLegacyMigrationAndCorruptStorageNeverBecomeEmpty() throws {
        let a = try terms(), p = try pending(a), decoder = JSONDecoder()
        let migrated = try decoder.decode(PaymentJournalState.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(try migrated.pending(), p)
        for value in ["{}", "{\"version\":1}", "{\"version\":2,\"entry\":null}", "{\"version\":1,\"entry\":{}}"] {
            XCTAssertThrowsError(try decoder.decode(PaymentJournalState.self, from: Data(value.utf8)))
        }
        let empty = try decoder.decode(PaymentJournalState.self, from: JSONEncoder().encode(PaymentJournalState()))
        XCTAssertNil(try empty.pending())
        var state = PaymentJournalState(); try state.beginApproval(a)
        XCTAssertThrowsError(try state.cancelApproval(terms())) // Same terms, different approval identity.
        try state.beginSigning(a); XCTAssertThrowsError(try state.cancelApproval(a))
    }
    func testTamperedApprovalAndClockRollbackFailBeforeAnyPrompt() async throws {
        let a = try terms(), data = try JSONEncoder().encode(a)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for badTime in [UInt64.max, UInt64(999), UInt64(1002)] {
            object["createdAt"] = badTime
            let bad = try JSONDecoder().decode(PaymentApproval.self, from: JSONSerialization.data(withJSONObject: object))
            let journal = ApprovalJournalFixture(), calls = ApprovalCalls(), f = fixtures(calls)
            do { _ = try await PaymentApprovalCoordinator(journal: journal, now: { 1001 }).approve(bad, with: f.0, signer: f.1, verifier: f.2); XCTFail("Accepted tampered creation time") } catch {}
            let sequence = calls.all(); XCTAssertTrue(sequence.isEmpty)
        }
        XCTAssertThrowsError(try a.validate(now: 1000))
    }
}
