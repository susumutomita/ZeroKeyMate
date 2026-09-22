import Foundation
import XCTest
@testable import MateCore

final class WeatherTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-22T08:30:00Z")!
    private func place() -> WeatherPlace {
        WeatherPlace(id: 1, name: "横浜市", latitude: 35.44778, longitude: 139.6425, timezone: "Asia/Tokyo", country: "日本", admin1: "神奈川県", feature_code: "PPLA")
    }
    private func response() -> [String: Any] { [
        "timezone": "Asia/Tokyo",
        "current_units": ["temperature_2m": "°C"],
        "daily_units": ["temperature_2m_min": "°C", "temperature_2m_max": "°C", "precipitation_probability_max": "%"],
        "current": ["time": "2026-09-22T17:30", "temperature_2m": 22.5, "weather_code": 61],
        "daily": ["time": ["2026-09-22","2026-09-23","2026-09-24"], "weather_code": [61,3,0], "temperature_2m_min": [18.0,19.0,20.0], "temperature_2m_max": [24.0,25.0,26.0], "precipitation_probability_max": [90,20,0]]
    ] }
    private func client(_ value: [String: Any]) throws -> OpenMeteoWeather {
        let data = try JSONSerialization.data(withJSONObject: value)
        return OpenMeteoWeather(fetch: { _ in data })
    }
    func testActualProviderValuesDatesAndSourcesDriveBothLanguages() async throws {
        let client = try client(response())
        let rain = try await client.forecast(for: place(), day: .today, now: now)
        XCTAssertEqual(rain.condition, 61)
        XCTAssertTrue(rain.text(japanese: true).contains("雨"))
        XCTAssertFalse(rain.text(japanese: true).contains("晴"))
        XCTAssertTrue(rain.text(japanese: false).contains("rain"))
        XCTAssertTrue(rain.text(japanese: false).contains("90%"))
        XCTAssertEqual(rain.sourceURL.host, "api.open-meteo.com")
        XCTAssertEqual(rain.date, "2026-09-22")
        let tomorrow = try await client.forecast(for: place(), day: .tomorrow, now: now)
        XCTAssertEqual(tomorrow.date, "2026-09-23")
        XCTAssertTrue(tomorrow.text(japanese: true).contains("くもり"))
        let current = try await client.forecast(for: place(), day: .current, now: now)
        XCTAssertTrue(current.text(japanese: true).contains("17:30"))
        XCTAssertTrue(current.text(japanese: true).contains("23度"))
    }
    func testLocationTimezoneGovernsTodayAcrossMidnight() async throws {
        var data = response()
        data["current"] = ["time": "2026-09-23T00:15", "temperature_2m": 22.5, "weather_code": 61]
        let report = try await client(data).forecast(for: place(), day: .today, now: ISO8601DateFormatter().date(from: "2026-09-22T15:30:00Z")!)
        XCTAssertEqual(report.date, "2026-09-23")
        XCTAssertEqual(report.condition, 3)
    }
    func testStaleFutureWrongUnitsMissingDateAndMalformedRangesFail() async throws {
        var variants: [[String: Any]] = []
        for time in ["2026-09-21T17:30", "2026-09-22T18:30", "bad"] {
            var data = response(); data["current"] = ["time": time, "temperature_2m": 20, "weather_code": 0]; variants.append(data)
        }
        var wrongUnits = response(); wrongUnits["current_units"] = ["temperature_2m": "°F"]; variants.append(wrongUnits)
        var wrongTimezone = response(); wrongTimezone["timezone"] = "Europe/London"; variants.append(wrongTimezone)
        for replacement: [String: Any] in [["time": ["2026-09-21"]], ["temperature_2m_min": [30,19,20]], ["weather_code": [0]], ["precipitation_probability_max": [101,20,0]]] {
            var data = response(); var daily = data["daily"] as! [String: Any]; daily.merge(replacement) { _, new in new }; data["daily"] = daily; variants.append(data)
        }
        for data in variants {
            do { _ = try await client(data).forecast(for: place(), day: .today, now: now); XCTFail("Invalid forecast accepted") }
            catch {}
        }
        XCTAssertFalse(WeatherReport.condition(999, japanese: true).contains("晴"))
    }
    func testGeocodingUsesOnlyCityAndFiltersNonPlaces() async throws {
        let payload = Data(#"{"results":[{"id":1,"name":"横浜市","latitude":35.4,"longitude":139.6,"timezone":"Asia/Tokyo","country":"日本","admin1":"神奈川県","feature_code":"PPLA"},{"id":2,"name":"横浜市児童遊園地","latitude":35.4,"longitude":139.6,"timezone":"Asia/Tokyo","feature_code":"PRK"}]}"#.utf8)
        let client = OpenMeteoWeather(fetch: { url in
            XCTAssertEqual(url.host, "geocoding-api.open-meteo.com")
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name,$0.value!) })
            XCTAssertEqual(query["name"], "横浜市")
            XCTAssertEqual(Set(query.keys), ["name","count","language","format"])
            return payload
        })
        let places = try await client.places(named: "横浜", japanese: true)
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places.first?.name, "横浜市")
    }
    func testUntrustedEndpointsAreRejectedBeforeNetwork() async {
        for value in ["http://api.open-meteo.com/v1/forecast", "https://example.org", "https://user:password@api.open-meteo.com"] {
            do { _ = try await WeatherHTTP.load(URL(string: value)!); XCTFail("Invalid endpoint accepted") } catch {}
        }
    }
}
