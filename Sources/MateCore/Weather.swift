import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WeatherDay: Int, Sendable { case current = -1, today = 0, tomorrow = 1, dayAfterTomorrow = 2 }
public struct WeatherPlace: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let timezone: String
    public let country: String?
    public let admin1: String?
    public let feature_code: String?
    public var label: String { [name, admin1, country].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ") }
}
public struct WeatherReport: Sendable {
    public let place: WeatherPlace
    public let day: WeatherDay
    public let date: String
    public let condition: Int
    public let temperature: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let rainProbability: Int?
    public let fetchedAt: Date
    public let sourceURL: URL
    public func text(japanese: Bool) -> String {
        let condition = Self.condition(condition, japanese: japanese)
        if day == .current, let temperature {
            return japanese ? "Open-Meteoによると、\(place.label)の\(date)時点の天気は\(condition)、気温は\(Int(temperature.rounded()))度です。" :
                "According to Open-Meteo, \(place.label) at \(date): \(condition), \(Int(temperature.rounded()))°C."
        }
        let minimum = Int((minimum ?? 0).rounded()), maximum = Int((maximum ?? 0).rounded())
        let probability = rainProbability.map { japanese ? "降水確率は\($0)%です。" : " Chance of precipitation: \($0)%." } ?? ""
        return japanese ? "Open-Meteoの予報では、\(place.label)の\(date)は\(condition)。最低\(minimum)度、最高\(maximum)度です。\(probability)" :
            "Open-Meteo forecasts \(condition) in \(place.label) on \(date), with a low of \(minimum)°C and a high of \(maximum)°C.\(probability)"
    }
    public static func condition(_ code: Int, japanese: Bool) -> String {
        let values: (String, String)
        switch code {
        case 0: values = ("快晴", "clear skies")
        case 1: values = ("おおむね晴れ", "mainly clear skies")
        case 2: values = ("晴れ時々くもり", "partly cloudy skies")
        case 3: values = ("くもり", "overcast skies")
        case 45,48: values = ("霧", "fog")
        case 51,53,55: values = ("霧雨", "drizzle")
        case 56,57,66,67: values = ("凍る雨", "freezing rain")
        case 61,63,65: values = ("雨", "rain")
        case 71,73,75,77: values = ("雪", "snow")
        case 80,81,82: values = ("にわか雨", "rain showers")
        case 85,86: values = ("にわか雪", "snow showers")
        case 95,96,99: values = ("雷雨", "thunderstorms")
        default: values = ("天候コードを解釈できません", "an unrecognized weather condition")
        }
        return japanese ? values.0 : values.1
    }
}
public protocol WeatherProviding: Sendable {
    func places(named: String, japanese: Bool) async throws -> [WeatherPlace]
    func forecast(for: WeatherPlace, day: WeatherDay, now: Date) async throws -> WeatherReport
}
public enum WeatherError: Error { case invalidResponse, unavailable }

/// Public, read-only weather. No conversation, GPS, cookies, wallet or identity data.
public struct OpenMeteoWeather: WeatherProviding {
    public typealias Fetch = @Sendable (URL) async throws -> Data
    private let fetch: Fetch
    public init(fetch: @escaping Fetch = { try await WeatherHTTP.load($0) }) { self.fetch = fetch }
    public func places(named name: String, japanese: Bool) async throws -> [WeatherPlace] {
        guard !name.isEmpty, name.utf8.count <= 160 else { throw WeatherError.invalidResponse }
        // GeoNames indexes Japanese municipalities by their formal names.
        // Bare 横浜 otherwise matches unrelated smaller settlements first.
        var search = name
        if name == "東京" { search = "東京都" }
        else if name.range(of: #"^[一-龯ぁ-んァ-ンー]{2,12}$"#, options: .regularExpression) != nil,
                !["都","道","府","県","市","区","町","村"].contains(where: name.hasSuffix) { search += "市" }
        func searchURL(_ term: String) -> URL { Self.url(host: "geocoding-api.open-meteo.com", path: "/v1/search", values: [
            "name": term, "count": "5", "language": japanese ? "ja" : "en", "format": "json"
        ]) }
        struct Response: Decodable { let results: [WeatherPlace]? }
        var result = try JSONDecoder().decode(Response.self, from: await fetch(searchURL(search))).results ?? []
        if result.isEmpty, search != name { result = try JSONDecoder().decode(Response.self, from: await fetch(searchURL(name))).results ?? [] }
        guard result.count <= 5, result.allSatisfy({ $0.latitude.isFinite && (-90...90).contains($0.latitude) && $0.longitude.isFinite && (-180...180).contains($0.longitude) && !$0.name.isEmpty && $0.label.count < 240 && TimeZone(identifier: $0.timezone) != nil }) else { throw WeatherError.invalidResponse }
        return Array(result.filter { $0.feature_code?.hasPrefix("PPL") == true || $0.feature_code?.hasPrefix("ADM") == true }.prefix(3))
    }
    public func forecast(for place: WeatherPlace, day: WeatherDay, now: Date = Date()) async throws -> WeatherReport {
        guard place.latitude.isFinite, (-90...90).contains(place.latitude), place.longitude.isFinite, (-180...180).contains(place.longitude), let timezone = TimeZone(identifier: place.timezone) else { throw WeatherError.invalidResponse }
        let url = Self.url(host: "api.open-meteo.com", path: "/v1/forecast", values: [
            "latitude": String(place.latitude), "longitude": String(place.longitude), "timezone": place.timezone,
            "current": "temperature_2m,weather_code", "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max", "forecast_days": "3", "temperature_unit": "celsius"
        ])
        return try Self.decode(try await fetch(url), place: place, day: day, now: now, sourceURL: url, timezone: timezone)
    }
    private static func url(host: String, path: String, values: [String: String]) -> URL {
        var url = URLComponents(); url.scheme = "https"; url.host = host; url.path = path
        url.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    private struct Response: Decodable {
        struct Current: Decodable { let time: String; let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable { let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]; let precipitation_probability_max: [Int?] }
        let timezone: String
        let current: Current
        let current_units: [String: String]
        let daily: Daily
        let daily_units: [String: String]
    }
    private static func decode(_ data: Data, place: WeatherPlace, day: WeatherDay, now: Date, sourceURL: URL, timezone: TimeZone) throws -> WeatherReport {
        let value = try JSONDecoder().decode(Response.self, from: data)
        guard value.timezone == place.timezone, value.current_units["temperature_2m"] == "°C", value.daily_units["temperature_2m_min"] == "°C", value.daily_units["temperature_2m_max"] == "°C", value.daily_units["precipitation_probability_max"] == "%" else { throw WeatherError.invalidResponse }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = timezone; formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"; formatter.isLenient = false
        guard let time = formatter.date(from: value.current.time), (-300...7_200).contains(now.timeIntervalSince(time)) else { throw WeatherError.invalidResponse }
        if day == .current {
            guard value.current.temperature_2m.isFinite, (-100...70).contains(value.current.temperature_2m) else { throw WeatherError.invalidResponse }
            return WeatherReport(place: place, day: day, date: value.current.time.replacingOccurrences(of: "T", with: " "), condition: value.current.weather_code, temperature: value.current.temperature_2m, minimum: nil, maximum: nil, rainProbability: nil, fetchedAt: now, sourceURL: sourceURL)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timezone
        guard let date = calendar.date(byAdding: .day, value: day.rawValue, to: now) else { throw WeatherError.invalidResponse }
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date), daily = value.daily
        guard let index = daily.time.firstIndex(of: key), Set(daily.time).count == daily.time.count,
              daily.weather_code.count == daily.time.count, daily.temperature_2m_max.count == daily.time.count,
              daily.temperature_2m_min.count == daily.time.count, daily.precipitation_probability_max.count == daily.time.count else { throw WeatherError.invalidResponse }
        let low = daily.temperature_2m_min[index], high = daily.temperature_2m_max[index], rain = daily.precipitation_probability_max[index]
        guard low.isFinite, high.isFinite, (-100...70).contains(low), (-100...70).contains(high), low <= high,
              rain.map({ (0...100).contains($0) }) ?? true else { throw WeatherError.invalidResponse }
        return WeatherReport(place: place, day: day, date: key, condition: daily.weather_code[index], temperature: nil, minimum: low, maximum: high, rainProbability: rain, fetchedAt: now, sourceURL: sourceURL)
    }
}

public enum WeatherHTTP {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 12; configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }()
    public static func load(_ url: URL) async throws -> Data {
        guard url.scheme == "https", ["api.open-meteo.com", "geocoding-api.open-meteo.com"].contains(url.host), url.user == nil, url.password == nil else { throw WeatherError.invalidResponse }
        var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData; request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url, data.count <= 128_000 else { throw WeatherError.unavailable }
        return data
    }
}
