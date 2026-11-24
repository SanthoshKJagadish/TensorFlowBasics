import Foundation

enum WeatherError: LocalizedError {
    case server(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .server(let reason): return "Weather service error: \(reason)"
        case .noData: return "No weather data was returned for this location."
        }
    }
}

// MARK: - Open-Meteo response types

struct OpenMeteoHourly: Decodable {
    let time: [String]
    let temperature: [Double?]
    let humidity: [Double?]
    let precipitation: [Double?]
    let cloudCover: [Double?]
    let pressure: [Double?]
    let windSpeed: [Double?]
    let windDirection: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case humidity = "relative_humidity_2m"
        case precipitation
        case cloudCover = "cloud_cover"
        case pressure = "pressure_msl"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
    }
}

struct OpenMeteoCurrent: Decodable {
    let time: String            // local time, "yyyy-MM-ddTHH:mm"
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
    }
}

struct OpenMeteoResponse: Decodable {
    let timezone: String
    let current: OpenMeteoCurrent?
    let hourly: OpenMeteoHourly
}

private struct OpenMeteoError: Decodable {
    let reason: String
}

struct GeocodingResponse: Decodable {
    struct Result: Decodable, Identifiable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?

        var place: Place {
            Place(name: name,
                  detail: [admin1, country].compactMap { $0 }.joined(separator: ", "),
                  latitude: latitude,
                  longitude: longitude)
        }
    }
    let results: [Result]?
}

// MARK: - Service

/// Fetches today's weather and the same calendar day in previous years from Open-Meteo
/// (free, no API key). Historical data comes from the ERA5-based archive API.
struct WeatherService: Sendable {
    private static let hourlyVariables =
        "temperature_2m,relative_humidity_2m,precipitation,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m"

    func fetchComparison(for place: Place, yearsBack: Int = 5) async throws -> ComparisonData {
        // 1. Today, in the place's own time zone.
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = Self.baseQuery(for: place) + [
            URLQueryItem(name: "current", value: "temperature_2m"),
            URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        let today: OpenMeteoResponse = try await Self.get(components.url!)
        guard let now = today.current else { throw WeatherError.noData }

        let todayString = String(now.time.prefix(10))
        let hour = Int(now.time.dropFirst(11).prefix(2)) ?? 12
        let parts = todayString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { throw WeatherError.noData }
        let (year, month, day) = (parts[0], parts[1], parts[2])

        var current = Self.snapshot(from: today.hourly, date: todayString, year: year,
                                    hour: hour, isCurrentYear: true)
        // Prefer the live "current" reading over the hourly model value.
        if let liveTemp = now.temperature { current.tempAtHour = liveTemp }

        // 2. Same calendar day in each previous year, fetched in parallel.
        let history = try await withThrowingTaskGroup(of: DaySnapshot.self) { group in
            for pastYear in (year - yearsBack)..<year {
                let date = Self.dateString(year: pastYear, month: month, day: day)
                group.addTask {
                    var c = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")!
                    c.queryItems = Self.baseQuery(for: place) + [
                        URLQueryItem(name: "start_date", value: date),
                        URLQueryItem(name: "end_date", value: date),
                    ]
                    let response: OpenMeteoResponse = try await Self.get(c.url!)
                    return Self.snapshot(from: response.hourly, date: date, year: pastYear,
                                         hour: hour, isCurrentYear: false)
                }
            }
            var results: [DaySnapshot] = []
            for try await snapshot in group { results.append(snapshot) }
            return results.sorted { $0.year < $1.year }
        }

        return ComparisonData(place: place, timezone: today.timezone, localHour: hour,
                              month: month, day: day, current: current, history: history)
    }

    func searchCities(_ query: String) async throws -> [GeocodingResponse.Result] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]
        let response: GeocodingResponse = try await Self.get(c.url!)
        return response.results ?? []
    }

    // MARK: Helpers

    private static func baseQuery(for place: Place) -> [URLQueryItem] {
        [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
            URLQueryItem(name: "hourly", value: hourlyVariables),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = (try? JSONDecoder().decode(OpenMeteoError.self, from: data))?.reason
            throw WeatherError.server(reason ?? "HTTP \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Feb 29 maps to Feb 28 in non-leap years.
    private static func dateString(year: Int, month: Int, day: Int) -> String {
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let safeDay = (month == 2 && day == 29 && !isLeap) ? 28 : day
        return String(format: "%04d-%02d-%02d", year, month, safeDay)
    }

    /// Aggregates the hourly series for one local date into a daily snapshot.
    static func snapshot(from hourly: OpenMeteoHourly, date: String, year: Int,
                         hour: Int, isCurrentYear: Bool) -> DaySnapshot {
        let indices = hourly.time.indices.filter { hourly.time[$0].hasPrefix(date) }

        func values(_ series: [Double?]) -> [Double] {
            indices.compactMap { $0 < series.count ? series[$0] : nil }
        }
        func mean(_ series: [Double?]) -> Double? {
            let v = values(series)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }

        let temps = values(hourly.temperature)
        let precip = values(hourly.precipitation)

        let hourPrefix = String(format: "%@T%02d", date, hour)
        let hourIndex = indices.first { hourly.time[$0].hasPrefix(hourPrefix) }
        let tempAtHour = hourIndex.flatMap { $0 < hourly.temperature.count ? hourly.temperature[$0] : nil }

        // Speed-weighted vector mean of wind direction.
        var u = 0.0, v = 0.0
        for i in indices where i < hourly.windSpeed.count && i < hourly.windDirection.count {
            guard let speed = hourly.windSpeed[i], let dir = hourly.windDirection[i] else { continue }
            let radians = dir * .pi / 180
            u += speed * sin(radians)
            v += speed * cos(radians)
        }
        var direction: Double? = nil
        if u != 0 || v != 0 {
            let degrees = atan2(u, v) * 180 / .pi
            direction = degrees < 0 ? degrees + 360 : degrees
        }

        return DaySnapshot(
            year: year,
            dateString: date,
            isCurrentYear: isCurrentYear,
            tempAtHour: tempAtHour,
            high: temps.max(),
            low: temps.min(),
            mean: temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count),
            precipitation: precip.isEmpty ? nil : precip.reduce(0, +),
            humidity: mean(hourly.humidity),
            cloudCover: mean(hourly.cloudCover),
            pressure: mean(hourly.pressure),
            windMax: values(hourly.windSpeed).max(),
            windDirection: direction
        )
    }
}
