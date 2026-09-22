import Foundation
import MateCore
import XCTest
@testable import ZeroKeyMate

private actor WeatherStub: WeatherProviding {
    var calls: [String] = []
    let unavailable: Bool
    let ambiguous: Bool
    var days: [WeatherDay] = []
    var selectedIDs: [Int] = []
    init(unavailable: Bool = true, ambiguous: Bool = false) { self.unavailable = unavailable; self.ambiguous = ambiguous }
    func places(named: String, japanese: Bool) async throws -> [WeatherPlace] {
        calls.append(named)
        let result = try JSONDecoder().decode([WeatherPlace].self, from: Data(#"[{"id":1,"name":"横浜市","latitude":35.4,"longitude":139.6,"timezone":"Asia/Tokyo","country":"日本","admin1":"神奈川県","feature_code":"PPLA"}]"#.utf8))
        if !ambiguous { return result }
        let second = try JSONDecoder().decode(WeatherPlace.self, from: Data(#"{"id":2,"name":"別の横浜","latitude":35.5,"longitude":139.7,"timezone":"Asia/Tokyo","feature_code":"PPL"}"#.utf8))
        return result + [second]
    }
    func forecast(for place: WeatherPlace, day: WeatherDay, now: Date) async throws -> WeatherReport {
        days.append(day); selectedIDs.append(place.id)
        if unavailable { throw WeatherError.unavailable }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let current = formatter.string(from: now)
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = (0...2).map { formatter.string(from: now.addingTimeInterval(Double($0) * 86_400)) }
        let json: [String: Any] = ["timezone":"Asia/Tokyo", "current_units":["temperature_2m":"°C"], "daily_units":["temperature_2m_min":"°C","temperature_2m_max":"°C","precipitation_probability_max":"%"], "current":["time":current,"weather_code":61,"temperature_2m":20], "daily":["time":dates,"weather_code":[61,3,0],"temperature_2m_min":[18,19,20],"temperature_2m_max":[24,25,26],"precipitation_probability_max":[90,20,0]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        return try await OpenMeteoWeather(fetch: { _ in data }).forecast(for: place, day: day, now: now)
    }
}
final class WeatherConversationTests: XCTestCase {
    func testMissingCityAsksAndProviderFailureNeverFallsThroughToSunnyModelReply() async throws {
        let stub = WeatherStub(), service = ConversationService(weather: WeatherStub())
        let question = try await service.reply(to: "今日の天気は？", history: [], observations: "", notes: "", replyLanguage: "日本語")
        XCTAssertTrue(question.text.contains("どの都市"))
        XCTAssertFalse(question.text.contains("晴れ"))
        let weather = WeatherConversation(provider: stub)
        _ = try await weather.reply(to: "今日の天気は？", history: [], japanese: true)
        let history = [ConversationTurn(isUser: true, text: "今日の天気は？"), .init(isUser: false, text: question.text)]
        let failure = try await weather.reply(to: "横浜", history: history, japanese: true)
        XCTAssertTrue(failure?.text.contains("取得できません") == true)
        XCTAssertFalse(failure?.text.contains("晴れ") == true)
        let sent = await stub.calls
        XCTAssertEqual(sent, ["横浜"])
        let reset = try await weather.reply(to: "横浜", history: [], japanese: true)
        XCTAssertNil(reset)
    }
    func testTranslationsAndTopicChangesDoNotSendConversationToWeatherAPI() async throws {
        let stub = WeatherStub(), weather = WeatherConversation(provider: WeatherStub())
        let translated = try await weather.reply(to: "Translate 'today's weather is sunny'", history: [], japanese: false)
        XCTAssertNil(translated)
        let isolated = WeatherConversation(provider: stub)
        _ = try await isolated.reply(to: "What's the weather today?", history: [], japanese: false)
        let history = [ConversationTurn(isUser: true, text: "What's the weather today?"), .init(isUser: false, text: "Which city?")]
        let unrelated = try await isolated.reply(to: "My name is Alice", history: history, japanese: false)
        XCTAssertNil(unrelated)
        let sent = await stub.calls
        XCTAssertTrue(sent.isEmpty)
    }
    func testFollowUpFetchesFreshDataAndClearingDropsTheCity() async throws {
        let stub = WeatherStub(unavailable: false), weather = WeatherConversation(provider: WeatherStub())
        let live = WeatherConversation(provider: stub)
        let first = try await live.reply(to: "横浜の天気は？", history: [], japanese: true)
        XCTAssertTrue(first?.text.contains("雨") == true)
        XCTAssertEqual(first?.source?.host, "api.open-meteo.com")
        let history = [ConversationTurn(isUser: true, text: "横浜の天気は？"), .init(isUser: false, text: first!.text)]
        let second = try await live.reply(to: "明日は？", history: history, japanese: true)
        XCTAssertTrue(second?.text.contains("くもり") == true)
        let days = await stub.days
        XCTAssertEqual(days, [.today,.tomorrow])
        let cleared = try await live.reply(to: "今日の天気は？", history: [], japanese: true)
        XCTAssertTrue(cleared?.text.contains("どの都市") == true)
        let other = try await weather.reply(to: "明日は？", history: [], japanese: true)
        XCTAssertNil(other)
    }
    func testAmbiguousCitiesNeverSelectFirstWithoutAnAnswer() async throws {
        let stub = WeatherStub(unavailable: false, ambiguous: true), weather: WeatherConversation
        weather = WeatherConversation(provider: stub)
        let question = try await weather.reply(to: "Weather in London", history: [], japanese: false)
        XCTAssertTrue(question?.text.contains("Which location") == true)
        let before = await stub.days
        XCTAssertTrue(before.isEmpty)
        let history = [ConversationTurn(isUser: true, text: "Weather in London"), .init(isUser: false, text: question!.text)]
        let answer = try await weather.reply(to: "二番", history: history, japanese: false)
        XCTAssertTrue(answer?.text.contains("rain") == true)
        let after = await stub.days
        XCTAssertEqual(after, [.today])
        let ids = await stub.selectedIDs
        XCTAssertEqual(ids, [2])
    }
    func testWeatherQuestionsKeepExplicitCityAndDateAndExcludeUnsafeLocations() {
        for (input, city, day) in [("横浜の今日の天気は？","横浜",WeatherDay.today),("明日の大阪の天気を教えて","大阪",.tomorrow),("What's the weather like in London tomorrow?","London",.tomorrow),("Weather in Tokyo, Japan today","Tokyo, Japan",.today)] {
            let value = WeatherQuestion.parse(input)
            XCTAssertEqual(value?.city, city, input)
            XCTAssertEqual(value?.day, day, input)
        }
        for input in ["今晴れ？","今日、傘いる？","Will it rain today?"] { XCTAssertNotNil(WeatherQuestion.parse(input),input) }
        for input in ["来週の天気は？","Weather in London yesterday","今夜の天気は？"] { XCTAssertTrue(WeatherQuestion.parse(input)?.unsupported == true,input) }
        for input in ["2", "二番", "two", "the second one"] { XCTAssertEqual(WeatherQuestion.choiceNumber(input), 2) }
        XCTAssertNil(WeatherQuestion.choiceNumber("99"))
        XCTAssertNil(WeatherQuestion.parse("いい天気だね"))
        XCTAssertNil(WeatherQuestion.cityAnswer("https://example.com"))
        XCTAssertNil(WeatherQuestion.cityAnswer("暗証番号は1234"))
    }
}

/// Opt-in by running this test class on a physical device. Fixed public city;
/// no GPS, microphone, camera, personal history or payment is used.
final class PhysicalWeatherTests: XCTestCase {
    func testLiveForecastAndTomorrowThroughTheConversationService() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Live provider acceptance is run explicitly on the physical phone")
        #else
        let service = ConversationService()
        var history: [ConversationTurn] = []
        for prompt in ["横浜の今日の天気は？", "明日は？"] {
            let reply = try await service.reply(to: prompt, history: history, observations: "", notes: "", replyLanguage: "日本語")
            let attachment = XCTAttachment(string: "Synthetic public city query: \(prompt)\nReply: \(reply.text)\nSource: \(reply.sourceURL?.absoluteString ?? "none")")
            attachment.name = "physical-live-weather"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(reply.sourceURL?.host, "api.open-meteo.com", reply.text)
            XCTAssertTrue(reply.text.contains("横浜市"), reply.text)
            XCTAssertTrue(reply.text.contains("Open-Meteo"), reply.text)
            history += [.init(isUser: true, text: prompt), .init(isUser: false, text: reply.text)]
        }
        #endif
    }
}
