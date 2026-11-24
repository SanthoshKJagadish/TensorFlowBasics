import SwiftUI

struct AISummaryCard: View {
    let state: WeatherViewModel.SummaryState
    let onRetry: () -> Void
    let onAddKey: () -> Void

    var body: some View {
        Card(title: "Why is today different?", systemImage: "sparkles") {
            switch state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Comparing today with last year…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .needsKey:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your Claude API key to get an AI explanation of today's weather compared with last year.")
                        .foregroundStyle(.secondary)
                    Button("Add API key", action: onAddKey)
                        .buttonStyle(.borderedProminent)
                }

            case .loaded(let summary):
                VStack(alignment: .leading, spacing: 8) {
                    if !summary.headline.isEmpty {
                        Text(summary.headline).font(.headline)
                    }
                    Text(summary.body)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("AI-generated from the data below. May be imperfect.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again", action: onRetry).buttonStyle(.bordered)
                }
            }
        }
    }
}
