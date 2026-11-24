import Foundation

/// A location the user is looking at.
struct Place: Codable, Hashable {
    var name: String
    var detail: String?
    var latitude: Double
    var longitude: Double
}

/// Weather for one calendar day (in the place's local time zone). All values are metric:
/// °C, mm, %, hPa, km/h, degrees.
struct DaySnapshot: Identifiable, Hashable {
    let year: Int
    let dateString: String          // yyyy-MM-dd, local to the place
    let isCurrentYear: Bool
    var tempAtHour: Double?         // temperature at the same local hour as "now"
    let high: Double?
    let low: Double?
    let mean: Double?
    let precipitation: Double?
    let humidity: Double?
    let cloudCover: Double?
    let pressure: Double?
    let windMax: Double?
    let windDirection: Double?      // speed-weighted mean direction the wind blows FROM

    var id: Int { year }

    /// SF Symbol that roughly describes the day.
    var symbolName: String {
        if let p = precipitation, p >= 1 {
            if let hi = high, hi <= 1 { return "cloud.snow.fill" }
            return p >= 10 ? "cloud.heavyrain.fill" : "cloud.rain.fill"
        }
        switch cloudCover ?? 0 {
        case 75...: return "cloud.fill"
        case 35..<75: return "cloud.sun.fill"
        default: return "sun.max.fill"
        }
    }
}

/// Today plus the same calendar day in previous years.
struct ComparisonData {
    let place: Place
    let timezone: String
    let localHour: Int
    let month: Int
    let day: Int
    let current: DaySnapshot
    let history: [DaySnapshot]       // oldest -> newest, excludes the current year

    var all: [DaySnapshot] { history + [current] }
    var lastYear: DaySnapshot? { history.last }

    /// Average of a value over the previous years (ignores missing values).
    func historicalAverage(_ value: (DaySnapshot) -> Double?) -> Double? {
        let values = history.compactMap(value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

enum UnitSystem: String, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }

    static var localeDefault: UnitSystem {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }

    var label: String { self == .metric ? "Metric (°C, mm, km/h)" : "Imperial (°F, in, mph)" }
    var tempSymbol: String { self == .metric ? "°C" : "°F" }
    var precipSymbol: String { self == .metric ? "mm" : "in" }
    var windSymbol: String { self == .metric ? "km/h" : "mph" }

    func temp(_ celsius: Double) -> Double { self == .metric ? celsius : celsius * 9 / 5 + 32 }
    func tempDelta(_ celsius: Double) -> Double { self == .metric ? celsius : celsius * 9 / 5 }
    func precip(_ mm: Double) -> Double { self == .metric ? mm : mm / 25.4 }
    func wind(_ kmh: Double) -> Double { self == .metric ? kmh : kmh / 1.609344 }

    func tempString(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return "\(Int(temp(celsius).rounded()))°"
    }

    func precipString(_ mm: Double?) -> String {
        guard let mm else { return "–" }
        return self == .metric
            ? String(format: "%.1f mm", mm)
            : String(format: "%.2f in", precip(mm))
    }

    func windString(_ kmh: Double?) -> String {
        guard let kmh else { return "–" }
        return String(format: "%.0f %@", wind(kmh), windSymbol)
    }
}

enum Compass {
    static func name(for degrees: Double?) -> String {
        guard let degrees else { return "–" }
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[index]
    }
}
