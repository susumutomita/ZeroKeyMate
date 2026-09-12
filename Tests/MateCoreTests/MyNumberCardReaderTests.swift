import XCTest
@testable import MateCore

@MainActor final class MyNumberCardReaderTests: XCTestCase {
    // Synthetic layout only, never a person's card dump.
    private func fixture(offset: Int = 32, date: String = "20000101") -> Data {
        var data = Data(repeating: 0, count: max(256, offset + 11))
        data[13] = UInt8(offset)
        data.replaceSubrange(offset..<(offset + 11), with: [0xDF, 0x24, 8] + Array(date.utf8))
        return data
    }
    func testReadsSequentiallyAndReturnsOnlyAnUnverifiedDate() async throws {
        var commands = [MyNumberCardCommand]()
        let data = fixture()
        let date = try await MyNumberCardReader.read(pin: "1234") { command in
            commands.append(command)
            return .init(data: command.instruction == 0xB0 ? data : Data())
        }
        XCTAssertEqual(commands.map(\.instruction), [0xA4, 0xA4, 0x20, 0xA4, 0xB0])
        XCTAssertEqual(commands[0].data, MyNumberCardReader.applicationID)
        XCTAssertEqual(commands[2].data, Data("1234".utf8))
        XCTAssertEqual(date.year, 2000)
    }
    func testIncorrectPINIsNeverRetriedAndDoesNotReadPII() async {
        var sent = [UInt8]()
        do {
            _ = try await MyNumberCardReader.read(pin: "1234") { command in
                sent.append(command.instruction)
                return command.instruction == 0x20 ? .init(sw1: 0x63, sw2: 0xC2) : .init()
            }
            XCTFail("PIN rejection was ignored")
        } catch { XCTAssertEqual(error as? MyNumberCardError, .pinRejected(remainingAttempts: 2)) }
        XCTAssertEqual(sent, [0xA4, 0xA4, 0x20])
    }
    func testFailedSelectionNeverSendsPIN() async {
        var count = 0
        do {
            _ = try await MyNumberCardReader.read(pin: "1234") { _ in
                count += 1; return .init(sw1: 0x6A, sw2: 0x82)
            }
            XCTFail("Failed selection was ignored")
        } catch { XCTAssertEqual(error as? MyNumberCardError, .commandRejected) }
        XCTAssertEqual(count, 1)
    }
    func testInvalidPINNeverContactsCard() async {
        for pin in ["", "123", "12345", "１２３４", "1a34"] {
            do {
                _ = try await MyNumberCardReader.read(pin: pin) { _ in XCTFail("Unexpected APDU"); return .init() }
                XCTFail("Invalid PIN accepted")
            } catch { XCTAssertEqual(error as? MyNumberCardError, .invalidPIN) }
        }
    }
    func testTruncatedAndWrongFieldCannotBecomeDate() async {
        var wrongTag = fixture(); wrongTag[33] = 0x23
        var badOffset = fixture(); badOffset[13] = 1
        var wrongLength = fixture(); wrongLength[34] = 7
        for data in [Data(), Data(repeating: 0, count: 14), wrongTag, badOffset, wrongLength, fixture(date: "20000230")] {
            do {
                _ = try await MyNumberCardReader.read(pin: "1234") { command in
                    .init(data: command.instruction == 0xB0 ? data : Data())
                }
                XCTFail("Malformed date accepted")
            } catch { XCTAssertTrue(error is MyNumberCardError) }
        }
    }
    func testDateAcrossPageBoundary() async throws {
        let data = fixture(offset: 250)
        var reads = [MyNumberCardCommand]()
        let date = try await MyNumberCardReader.read(pin: "1234") { command in
            guard command.instruction == 0xB0 else { return .init() }
            reads.append(command)
            let offset = Int(command.p1) * 256 + Int(command.p2)
            return .init(data: Data(data[offset..<(offset + command.responseLength)]))
        }
        XCTAssertEqual(date.year, 2000)
        XCTAssertEqual(reads.map(\.responseLength), [256, 5])
    }
    func testInvalidCalendarDatesAndLeapYears() throws {
        _ = try UnverifiedCardBirthDate(ascii: Data("20000229".utf8))
        for value in ["19000229", "20001301", "20000010", "20000100", "20000431", "abcdefgh"] {
            XCTAssertThrowsError(try UnverifiedCardBirthDate(ascii: Data(value.utf8)))
        }
    }
    func testCancellationBeforeStartSendsNothing() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MyNumberCardReader.read(pin: "1234") { _ in XCTFail("APDU after cancellation"); return .init() }
        }
        do { _ = try await task.value; XCTFail("Cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
