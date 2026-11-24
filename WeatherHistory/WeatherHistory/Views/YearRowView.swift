import SwiftUI

struct YearRowView: View {
    let snapshot: DaySnapshot
    let units: UnitSystem
    let hour: Int
    let isLastYear: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(snapshot.year))
                    .font(.headline)
                    .foregroundStyle(snapshot.isCurrentYear ? Color.accentColor : .primary)
                if snapshot.isCurrentYear {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                } else if isLastYear {
                    Text("Last year").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, alignment: .leading)

            Image(systemName: snapshot.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("H \(units.tempString(snapshot.high))  L \(units.tempString(snapshot.low))")
                    .font(.subheadline)
                Text("\(Image(systemName: "drop")) \(units.precipString(snapshot.precipitation))  \(Image(systemName: "wind")) \(units.windString(snapshot.windMax)) \(Compass.name(for: snapshot.windDirection))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(units.tempString(snapshot.tempAtHour))
                    .font(.title2.weight(.semibold))
                Text(String(format: "at %02d:00", hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
