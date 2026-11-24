import SwiftUI
import Charts

/// Low–high range bars per year, with a dot for the temperature at the current local hour.
struct ComparisonChartView: View {
    let data: ComparisonData
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(data.all) { snapshot in
                    if let low = snapshot.low, let high = snapshot.high {
                        BarMark(
                            x: .value("Year", String(snapshot.year)),
                            yStart: .value("Low", units.temp(low)),
                            yEnd: .value("High", units.temp(high)),
                            width: .ratio(0.45)
                        )
                        .cornerRadius(6)
                        .foregroundStyle(snapshot.isCurrentYear ? Color.accentColor : Color.gray.opacity(0.4))
                    }
                    if let temp = snapshot.tempAtHour {
                        PointMark(
                            x: .value("Year", String(snapshot.year)),
                            y: .value("At this hour", units.temp(temp))
                        )
                        .symbolSize(70)
                        .foregroundStyle(snapshot.isCurrentYear ? Color.orange : Color.primary)
                        .annotation(position: .top, spacing: 4) {
                            Text(units.tempString(temp))
                                .font(.caption2.weight(snapshot.isCurrentYear ? .bold : .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let average = data.historicalAverage({ $0.tempAtHour }) {
                    RuleMark(y: .value("5-yr average", units.temp(average)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxisLabel(units.tempSymbol)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 230)

            HStack(spacing: 14) {
                legend(color: .gray.opacity(0.5), shape: "rectangle.fill", text: "Low–high")
                legend(color: .primary, shape: "circle.fill", text: String(format: "At %02d:00", data.localHour))
                legend(color: .secondary, shape: "line.horizontal.3", text: "5-yr avg")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(color: Color, shape: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: shape).foregroundStyle(color)
            Text(text)
        }
    }
}
