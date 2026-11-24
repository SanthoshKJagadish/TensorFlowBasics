import SwiftUI

struct TodayHeaderView: View {
    let data: ComparisonData
    let units: UnitSystem

    var body: some View {
        VStack(spacing: 6) {
            if let detail = data.place.detail, !detail.isEmpty {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(dateLabel).font(.subheadline).foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: data.current.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                Text(units.tempString(data.current.tempAtHour))
                    .font(.system(size: 72, weight: .thin, design: .rounded))
            }

            Text("H \(units.tempString(data.current.high))  ·  L \(units.tempString(data.current.low))")
                .font(.headline)

            if let chip = lastYearChip {
                Text(chip.text)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(chip.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(chip.color)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var dateLabel: String {
        var components = DateComponents()
        components.year = data.current.year
        components.month = data.month
        components.day = data.day
        components.hour = data.localHour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: components) else { return "" }
        let style = Date.FormatStyle(timeZone: calendar.timeZone)
        return date.formatted(style.weekday(.wide).month(.abbreviated).day().hour())
    }

    private var lastYearChip: (text: String, color: Color)? {
        guard let now = data.current.tempAtHour, let then = data.lastYear?.tempAtHour else { return nil }
        let delta = units.tempDelta(now - then)
        let rounded = Int(abs(delta).rounded())
        if rounded == 0 { return ("About the same as this time last year", .secondary) }
        return delta > 0
            ? ("\(rounded)° warmer than this time last year", .orange)
            : ("\(rounded)° cooler than this time last year", .blue)
    }
}
