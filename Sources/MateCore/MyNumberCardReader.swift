import Foundation

/// ISO 7816 commands adapted from knocks-public/2024-CircuitBreaker (MIT),
/// commit 9f228ff782e5c57e6f48de3c3d7f4f2ea5b891ea, NfcModule.swift.
/// This reads the input-assistance application, NOT an authenticated JPKI credential.
public struct MyNumberCardCommand: Equatable, Sendable {
    public let instructionClass: UInt8
    public let instruction: UInt8
    public let p1: UInt8
    public let p2: UInt8
    public let data: Data
    public let responseLength: Int

    public init(instructionClass: UInt8 = 0, instruction: UInt8, p1: UInt8, p2: UInt8, data: Data = Data(), responseLength: Int = -1) {
        self.instructionClass = instructionClass
        self.instruction = instruction; self.p1 = p1; self.p2 = p2
        self.data = data; self.responseLength = responseLength
    }
}

public struct MyNumberCardResponse: Sendable {
    public let data: Data
    public let sw1: UInt8
    public let sw2: UInt8
    public init(data: Data = Data(), sw1: UInt8 = 0x90, sw2: UInt8 = 0x00) {
        self.data = data; self.sw1 = sw1; self.sw2 = sw2
    }
}

public enum MyNumberCardError: Error, Equatable {
    case invalidPIN, pinRejected(remainingAttempts: Int), pinBlocked
    case commandRejected, malformedResponse, invalidBirthDate, requestExpired
}

/// Deliberately distinct from a verified age credential. Not Codable and never
/// stored by the reader. No method on this value can authorize an order.
public struct UnverifiedCardBirthDate: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(ascii: Data) throws {
        let bytes = Array(ascii)
        guard bytes.count == 8, bytes.allSatisfy({ (48...57).contains($0) }) else {
            throw MyNumberCardError.invalidBirthDate
        }
        func number(_ range: Range<Int>) -> Int { range.reduce(0) { $0 * 10 + Int(bytes[$1] - 48) } }
        let year = number(0..<4), month = number(4..<6), day = number(6..<8)
        guard (1868...9999).contains(year), (1...12).contains(month) else {
            throw MyNumberCardError.invalidBirthDate
        }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { throw MyNumberCardError.invalidBirthDate }
        self.year = year; self.month = month; self.day = day
    }
}

public enum MyNumberCardReader {
    public static let applicationID = Data([0xD3, 0x92, 0x10, 0x00, 0x31, 0x00, 0x01, 0x01, 0x04, 0x08])

    /// Sequential APDUs; at most one PIN verification per explicit read.
    /// The callback must not log commands or responses, which can contain PII.
    @MainActor public static func read(pin: String,
                            send: (MyNumberCardCommand) async throws -> MyNumberCardResponse) async throws -> UnverifiedCardBirthDate {
        let pinBytes = Array(pin.utf8)
        guard pinBytes.count == 4, pinBytes.allSatisfy({ (48...57).contains($0) }) else {
            throw MyNumberCardError.invalidPIN
        }
        func exchange(_ command: MyNumberCardCommand) async throws -> Data {
            try Task.checkCancellation()
            let response = try await send(command)
            try Task.checkCancellation()
            guard response.sw1 == 0x90 && response.sw2 == 0 else {
                if command.instruction == 0x20 {
                    if response.sw1 == 0x69 && response.sw2 == 0x83 { throw MyNumberCardError.pinBlocked }
                    if response.sw1 == 0x63 && response.sw2 & 0xF0 == 0xC0 {
                        let count = Int(response.sw2 & 0x0F)
                        if count == 0 { throw MyNumberCardError.pinBlocked }
                        throw MyNumberCardError.pinRejected(remainingAttempts: count)
                    }
                }
                throw MyNumberCardError.commandRejected
            }
            return response.data
        }
        _ = try await exchange(.init(instruction: 0xA4, p1: 0x04, p2: 0x0C, data: applicationID))
        _ = try await exchange(.init(instruction: 0xA4, p1: 0x02, p2: 0x0C, data: Data([0x00, 0x11])))
        _ = try await exchange(.init(instruction: 0x20, p1: 0x00, p2: 0x80, data: Data(pinBytes)))
        _ = try await exchange(.init(instruction: 0xA4, p1: 0x02, p2: 0x0C, data: Data([0x00, 0x02])))

        // Read only the bounded portion needed for the birth-date field. The
        // source layout has its birth-date offset at byte 13; never index first.
        var contents = try await exchange(.init(instruction: 0xB0, p1: 0, p2: 0, responseLength: 256))
        guard contents.count >= 16, contents.count <= 256 else { throw MyNumberCardError.malformedResponse }
        let offset = Int(contents[13])
        guard offset >= 16, offset <= 255 else { throw MyNumberCardError.malformedResponse }
        let needed = offset + 3 + 8
        if contents.count < needed {
            // A valid large address can put the eight-byte date across the first
            // page. A short first page cannot be continued by guessing offsets.
            guard contents.count == 256 else { throw MyNumberCardError.malformedResponse }
            let remainder = try await exchange(.init(instruction: 0xB0, p1: 1, p2: 0, responseLength: needed - 256))
            guard remainder.count == needed - 256 else { throw MyNumberCardError.malformedResponse }
            contents.append(remainder)
        }
        guard contents[offset] == 0xDF, contents[offset + 1] == 0x24, contents[offset + 2] == 8 else {
            throw MyNumberCardError.malformedResponse
        }
        return try UnverifiedCardBirthDate(ascii: Data(contents[(offset + 3)..<needed]))
    }
}
