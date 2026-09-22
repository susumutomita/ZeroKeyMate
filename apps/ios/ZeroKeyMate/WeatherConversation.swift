import Foundation
import MateCore

/// Read-only weather routing, before free-form generation. Dates and weather
/// values come from the provider; the model cannot manufacture a forecast.
actor WeatherConversation {
    struct Reply: Sendable { let text: String; var source: URL? = nil }
    private let provider: any WeatherProviding
    private var place: WeatherPlace?
    private var pendingDay: WeatherDay?
    private var choices: [WeatherPlace] = []
    init(provider: any WeatherProviding = OpenMeteoWeather()) { self.provider = provider }

    func reply(to input: String, history: [ConversationTurn], japanese: Bool) async throws -> Reply? {
        if history.isEmpty { place = nil; pendingDay = nil; choices = [] }
        guard !WeatherQuestion.isLanguageTask(input) else { pendingDay = nil; choices = []; return nil }
        let query = WeatherQuestion.parse(input)
        var selected: WeatherPlace?
        var city: String?
        var day: WeatherDay
        if let query {
            guard !query.unsupported else {
                pendingDay = nil; choices = []
                return Reply(text: japanese ? "確認できるのは現在・今日・明日・明後日の天気です。都市名と知りたい日を教えてください。" : "I can check current weather, today, tomorrow or the day after tomorrow. Which city and day?")
            }
            day = query.day; city = query.city; selected = city == nil ? place : nil
            choices = []
        } else if let pendingDay {
            day = pendingDay
            if !choices.isEmpty, let number = WeatherQuestion.choiceNumber(input), choices.indices.contains(number - 1) {
                selected = choices[number - 1]
            } else if let value = WeatherQuestion.cityAnswer(input) { city = value }
            else { self.pendingDay = nil; choices = []; return nil }
        } else if let remembered = place, let followUp = WeatherQuestion.dayFollowUp(input) {
            day = followUp; selected = remembered
        } else { return nil }
        pendingDay = nil
        do {
            if let city {
                let found = try await provider.places(named: city, japanese: japanese)
                try Task.checkCancellation()
                if found.isEmpty {
                    return Reply(text: japanese ? "その都市は見つかりませんでした。国名も付けて、もう一度天気を聞いてください。" : "I couldn't find that city. Ask again with the city and country.")
                }
                if found.count > 1 {
                    choices = found; pendingDay = day
                    let list = found.enumerated().map { "\($0.offset + 1). \($0.element.label)" }.joined(separator: "\n")
                    return Reply(text: (japanese ? "同じ名前の場所があります。番号で教えてください。\n" : "Which location? Tell me its number.\n") + list, source: URL(string: "https://open-meteo.com/en/docs/geocoding-api"))
                }
                selected = found[0]
            }
            guard let selected else {
                pendingDay = day
                return Reply(text: japanese ? "どの都市の天気を調べますか？都市名をOpen-Meteoに送って予報を確認します。" : "Which city's weather? I'll send the city name to Open-Meteo to check its forecast.")
            }
            let report = try await provider.forecast(for: selected, day: day, now: Date())
            try Task.checkCancellation()
            place = selected; choices = []
            return Reply(text: report.text(japanese: japanese), source: report.sourceURL)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            choices = []; pendingDay = nil
            return Reply(text: japanese ? "最新の天気を取得できませんでした。今の天気は確認できていません。少し待って、もう一度聞いてください。" : "I couldn't retrieve the latest forecast, so I can't confirm the weather. Please try again shortly.")
        }
    }
}

enum WeatherQuestion {
    struct Query { let day: WeatherDay; let city: String?; let unsupported: Bool }
    private static func clean(_ input: String) -> String { input.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?？。.!！"))) }
    static func isLanguageTask(_ input: String) -> Bool {
        input.range(of: #"^(?:please\s+)?(?:translate|how do (?:you|i) say)\b|^what does .+ mean|翻訳|英訳|和訳|英語にして|日本語にして|に訳して"#, options: [.regularExpression,.caseInsensitive]) != nil
    }
    static func parse(_ input: String) -> Query? {
        let value = clean(input)
        let lower = value.lowercased()
        // Reports about one's day remain conversation. Direct weather questions
        // take the live-data route, including an unspecified location.
        guard input.lowercased().range(of: #"\b(weather|forecast|temperature)\b|天気|天候|予報|気温|(?:雨|晴れ|雪|傘).*(?:[？?]|かな|ですか|降る|降りますか|必要|いる)|\b(?:will it|is it|do i need).*(?:rain|snow|sunny|umbrella)|\b(?:rain|snow|sunny|umbrella).*\?"#, options: .regularExpression) != nil else { return nil }
        if lower.range(of: #"(?:いい天気|良い天気|晴れ)(?:だね|ですね|だったね)$|^(?:the weather was|it was sunny)\b"#, options: .regularExpression) != nil { return nil }
        let unsupported = lower.range(of: #"昨日|先週|来週|来月|週末|今夜|今晩|何時|[0-9０-９]+[月日時]|yesterday|last |next |weekend|tonight|hourly|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\b\d"#, options: .regularExpression) != nil
        let day: WeatherDay = lower.contains("明後日") || lower.contains("あさって") || lower.contains("day after tomorrow") ? .dayAfterTomorrow :
            lower.contains("明日") || lower.contains("あした") || lower.contains("tomorrow") ? .tomorrow :
            lower.hasPrefix("今") && !lower.hasPrefix("今日") || lower.contains("今の") || lower.contains("now") || lower.contains("current") || lower.contains("is it") ? .current : .today
        var city: String?
        let patterns = [
            #"^(?:(?:今日|明日|明後日|今)の)?(.{1,50}?)の(?:(?:今日|明日|明後日|今)の)?(?:天気|天候|予報|気温)(?:は|を教えて|を調べて|どう|どうですか|はどう|はどうですか|を教えてください)?$"#,
            #"(?i)^(?:(?:what(?:'s| is)|how(?:'s| is))\s+)?(?:the\s+)?(?:weather|forecast|temperature)(?:\s+like)?(?:\s+(?:today|tomorrow|now))?\s+(?:in|for)\s+(.+?)(?:\s+(?:today|tomorrow|right now|the day after tomorrow))?$"#
        ]
        for pattern in patterns {
            if let capture = match(pattern, value), let parsed = cityAnswer(capture), !["今日","明日","明後日","今","現在","ここ","こっち"].contains(parsed) { city = parsed; break }
        }
        return Query(day: day, city: city, unsupported: unsupported)
    }
    static func dayFollowUp(_ input: String) -> WeatherDay? {
        switch clean(input).lowercased() {
        case "明日は", "明日", "あしたは", "tomorrow", "what about tomorrow", "and tomorrow": return .tomorrow
        case "明後日は", "あさっては", "the day after tomorrow", "what about the day after tomorrow": return .dayAfterTomorrow
        case "今日は", "今日", "today", "what about today": return .today
        case "今は", "今の天気", "now", "what about now": return .current
        default: return nil
        }
    }
    static func choiceNumber(_ input: String) -> Int? {
        let value = clean(input).lowercased()
        for (number, answers) in [(1, ["1", "１", "一", "一番", "1番", "one", "first", "the first one"]),
                                  (2, ["2", "２", "二", "二番", "2番", "two", "second", "the second one"]),
                                  (3, ["3", "３", "三", "三番", "3番", "three", "third", "the third one"])] {
            if answers.contains(value) { return number }
        }
        return nil
    }
    static func cityAnswer(_ input: String) -> String? {
        let value = clean(input).replacingOccurrences(of: #"^(?:in|for)\s+"#, with: "", options: [.regularExpression,.caseInsensitive])
            .replacingOccurrences(of: #"(?:です|だよ|で|でお願い|でお願いします)$"#, with: "", options: .regularExpression)
        guard (2...50).contains(value.count), value.range(of: #"^[\p{L}\p{M}]+(?:(?:[ '-]|, ?)[\p{L}\p{M}]+){0,4}$"#, options: .regularExpression) != nil,
              !["はい","いいえ","ありがとう","おやすみ","こんにちは","やめて","キャンセル","yes","no","thanks","hello","cancel","stop"].contains(value.lowercased()),
              value.range(of: #"名前|好き|苦手|買って|支払|暗証|password|\b(?:my|i|you|please|am|is|are)\b"#, options: [.regularExpression,.caseInsensitive]) == nil else { return nil }
        return value
    }
    private static func match(_ pattern: String, _ value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}
