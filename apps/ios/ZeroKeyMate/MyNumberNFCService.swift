import Foundation
import Combine
@preconcurrency import CoreNFC
import MateCore

enum CardScanError: Error, Equatable { case unavailable, busy, cancelled, multipleCards, wrongCard, connectionFailed }

/// Owns one explicitly started NFC session. No persistence, network, logging or
/// automatic retries; invalidation resolves the caller rather than hanging it.
@MainActor
final class MyNumberNFCService: NSObject, ObservableObject, @preconcurrency NFCTagReaderSessionDelegate {
    private enum ReadKind { case birthDate, authentication(JPKIChallenge) }
    private enum ReadResult { case birthDate(UnverifiedCardBirthDate), authentication(JPKILocalCredential) }
    @Published private(set) var scanning = false
    private var session: NFCTagReaderSession?
    private var result: CheckedContinuation<ReadResult, Error>?
    private var readKind = ReadKind.birthDate
    private var exchangeID = UUID()
    private var exchangeResult: CheckedContinuation<MyNumberCardResponse, Error>?
    private var readTask: Task<Void, Never>?
    private var pin = ""
    private var connected = false
    private var operationID = UUID()
    private var card: (any NFCISO7816Tag)?

    var available: Bool { NFCTagReaderSession.readingAvailable }

    func scan(pin: String) async throws -> UnverifiedCardBirthDate {
        guard case .birthDate(let date) = try await begin(pin: pin, kind: .birthDate) else { throw CardScanError.wrongCard }
        return date
    }

    /// Called only after reviewing an order and explicitly entering the signing
    /// PIN. The government credential and card signature stay on this phone.
    func authenticate(pin: String, challenge: JPKIChallenge) async throws -> JPKILocalCredential {
        guard case .authentication(let credential) = try await begin(pin: pin, kind: .authentication(challenge)) else { throw CardScanError.wrongCard }
        return credential
    }

    private func begin(pin: String, kind: ReadKind) async throws -> ReadResult {
        guard !scanning else { throw CardScanError.busy }
        guard available else { throw CardScanError.unavailable }
        switch kind {
        case .birthDate:
            guard pin.utf8.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }) else { throw MyNumberCardError.invalidPIN }
        case .authentication:
            guard JPKICardReader.validSigningPIN(pin) else { throw MyNumberCardError.invalidPIN }
        }
        try Task.checkCancellation()
        let readID = UUID()
        operationID = readID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.pin = pin
                self.readKind = kind
                self.result = continuation
                self.scanning = true
                self.connected = false
                let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main)
                self.session = session
                session?.alertMessage = L10n.text("Hold your My Number card against the top of your iPhone.")
                guard let session else { finish(.failure(CardScanError.unavailable)); return }
                session.begin()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.operationID == readID else { return }
                self?.cancel()
            }
        }
    }

    func cancel() { finish(.failure(CardScanError.cancelled)) }

    private func finish(_ outcome: Result<ReadResult, Error>) {
        guard let continuation = result else { return }
        result = nil
        let pendingExchange = exchangeResult
        exchangeResult = nil
        pendingExchange?.resume(throwing: CardScanError.cancelled)
        pin = ""
        readKind = .birthDate
        card = nil
        scanning = false
        readTask?.cancel()
        readTask = nil
        let previous = session
        session = nil
        previous?.invalidate()
        continuation.resume(with: outcome)
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // CoreNFC delegates use the explicitly supplied .main queue. Keep the
        // non-Sendable tag/session objects on that actor, including callbacks.
        guard self.session === session else { return }
        self.finish(.failure(CardScanError.cancelled))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
            guard self.session === session, !self.connected else { return }
            guard tags.count == 1 else { self.finish(.failure(CardScanError.multipleCards)); return }
            guard case .iso7816(let card) = tags[0] else { self.finish(.failure(CardScanError.wrongCard)); return }
            self.connected = true
            self.card = card
            let operationID = self.operationID
            session.connect(to: tags[0]) { [weak self] error in
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.operationID == operationID, self.scanning else { return }
                    guard !failed else { self.finish(.failure(CardScanError.connectionFailed)); return }
                    self.readConnectedCard(operationID: operationID)
                }
            }
    }

    private func readConnectedCard(operationID: UUID) {
        let oneReadPIN = pin
        let kind = readKind
        pin = ""
        readTask = Task { @MainActor in
            do {
                let output: ReadResult
                switch kind {
                case .birthDate:
                    output = .birthDate(try await MyNumberCardReader.read(pin: oneReadPIN) { command in
                        try await self.send(command, operationID: operationID)
                    })
                case .authentication(let challenge):
                    let authentication = try await JPKICardReader.authenticate(pin: oneReadPIN, challenge: challenge) { command in
                        try await self.send(command, operationID: operationID)
                    }
                    output = .authentication(try JPKICredentialVerifier.verify(authentication, challenge: challenge))
                }
                guard self.operationID == operationID, self.scanning else { return }
                self.session?.alertMessage = L10n.text("Card read. No personal information was sent.")
                self.finish(.success(output))
            } catch {
                guard self.operationID == operationID, self.scanning else { return }
                self.finish(.failure(error))
            }
        }
    }

    private func send(_ command: MyNumberCardCommand, operationID: UUID) async throws -> MyNumberCardResponse {
        try Task.checkCancellation()
        guard self.operationID == operationID, scanning, let card else { throw CardScanError.cancelled }
        let ticket = UUID()
        exchangeID = ticket
        let apdu = NFCISO7816APDU(instructionClass: command.instructionClass, instructionCode: command.instruction,
            p1Parameter: command.p1, p2Parameter: command.p2, data: command.data, expectedResponseLength: command.responseLength)
        return try await withCheckedThrowingContinuation { continuation in
            exchangeResult = continuation
            card.sendCommand(apdu: apdu) { [weak self] data, sw1, sw2, error in
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.operationID == operationID, self.exchangeID == ticket,
                          let waiting = self.exchangeResult else { return }
                    self.exchangeResult = nil
                    if failed { waiting.resume(throwing: CardScanError.connectionFailed) }
                    else { waiting.resume(returning: MyNumberCardResponse(data: data, sw1: sw1, sw2: sw2)) }
                }
            }
        }
    }
}
