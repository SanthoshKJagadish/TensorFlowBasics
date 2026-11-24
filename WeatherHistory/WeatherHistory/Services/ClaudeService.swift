import Foundation

enum ClaudeError: LocalizedError {
    case api(String)
    case refused
    case empty

    var errorDescription: String? {
        switch self {
        case .api(let message): return message
        case .refused: return "The AI declined to summarize this request."
        case .empty: return "The AI returned an empty summary."
        }
    }
}

struct WeatherSummary: Equatable {
    let headline: String
    let body: String
}

/// Calls the Claude Messages API over plain HTTPS (there is no official Swift SDK).
struct ClaudeService {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"

    let apiKey: String

    func summarize(_ data: ComparisonData, units: UnitSystem) async throws -> WeatherSummary {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 8000,
            // Low effort keeps the response fast for a mobile UI; raise to "medium" for deeper analysis.
            "output_config": ["effort": "low"],
            // If Claude declines, let the API retry on a suitable fallback model automatically.
            "fallbacks": "default",
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": Self.userPrompt(for: data, units: units)]
            ],
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: responseData) {
                throw ClaudeError.api(Self.friendlyMessage(status: status, apiMessage: envelope.error.message))
            }
            throw ClaudeError.api(Self.friendlyMessage(status: status, apiMessage: nil))
        }

        let message = try JSONDecoder().decode(MessageResponse.self, from: responseData)
        if message.stopReason == "refusal" { throw ClaudeError.refused }

        let text = message.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClaudeError.empty }

        // First line = headline, rest = body.
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let headline = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
        let rest = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return rest.isEmpty ? WeatherSummary(headline: "", body: headline)
                            : WeatherSummary(headline: headline, body: rest)
    }

    // MARK: Prompt

    static let systemPrompt = """
    You are a friendly meteorologist inside a weather app. The user sees today's weather at \
    their location next to the same calendar day in each of the previous five years.

    Explain in plain language how today compares with the same day last year (the main \
    comparison) and with the five-year range, and why. Ground every explanation in the data \
    you are given, for example: a change in wind direction bringing air from a warmer, colder, \
    wetter or drier region; higher pressure (settled, clearer weather) versus lower pressure \
    (unsettled, cloudier, wetter); cloud cover (cloudy days have a smaller gap between high \
    and low, clear nights get colder); humidity and rain.

    If the difference is small, say so plainly and explain that this is normal day-to-day \
    variability. A single day is weather, not climate: do not attribute one day to climate \
    change, though you may mention a broader seasonal pattern as hedged context. Do not invent \
    facts the data does not support, such as named storms or specific events.

    Format: the first line is a headline of at most 8 words with no trailing punctuation. \
    Then a blank line, then at most two short paragraphs, under 130 words in total. Plain \
    text only: no markdown, no bullet points.
    """

    static func userPrompt(for data: ComparisonData, units u: UnitSystem) -> String {
        let monthName = Calendar(identifier: .gregorian).monthSymbols[data.month - 1]
        let hourLabel = String(format: "%02d:00", data.localHour)

        func t(_ v: Double?) -> String { v.map { String(format: "%.1f", u.temp($0)) } ?? "n/a" }
        func p(_ v: Double?) -> String { v.map { String(format: u == .metric ? "%.1f" : "%.2f", u.precip($0)) } ?? "n/a" }
        func w(_ v: Double?) -> String { v.map { String(format: "%.0f", u.wind($0)) } ?? "n/a" }
        func pct(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "n/a" }
        func hpa(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "n/a" }

        var lines: [String] = []
        let where_ = [data.place.name, data.place.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        lines.append("Location: \(where_) (lat \(String(format: "%.2f", data.place.latitude)), lon \(String(format: "%.2f", data.place.longitude)))")
        lines.append("Date: \(monthName) \(data.day), current local time \(hourLabel) (\(data.timezone))")
        lines.append("Units: temperature \(u.tempSymbol), precipitation \(u.precipSymbol), wind \(u.windSymbol), pressure hPa, humidity and cloud cover %")
        lines.append("")
        lines.append("year | temp at \(hourLabel) | high | low | daily mean | precipitation | mean humidity | mean cloud cover | mean sea-level pressure | max wind | prevailing wind from")
        for s in data.all {
            let label = s.isCurrentYear ? "\(s.year) (TODAY; hours after now are forecast)" : "\(s.year)"
            lines.append([label, t(s.tempAtHour), t(s.high), t(s.low), t(s.mean), p(s.precipitation),
                          pct(s.humidity), pct(s.cloudCover), hpa(s.pressure), w(s.windMax),
                          Compass.name(for: s.windDirection)].joined(separator: " | "))
        }
        lines.append("")
        lines.append("Explain how today compares with the same day last year and with the five-year range, and why.")
        return lines.joined(separator: "\n")
    }

    private static func friendlyMessage(status: Int, apiMessage: String?) -> String {
        switch status {
        case 401: return "Your Claude API key was rejected. Check it in Settings."
        case 429: return "Too many requests right now. Try again in a moment."
        case 529, 500...599: return "The AI service is busy. Try again shortly."
        default: return apiMessage ?? "AI request failed (HTTP \(status))."
        }
    }

    // MARK: Response types

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let type: String; let message: String }
        let error: Detail
    }
}
