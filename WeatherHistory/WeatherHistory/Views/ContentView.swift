import SwiftUI

struct ContentView: View {
    @State private var model = WeatherViewModel()
    @AppStorage("units") private var units: UnitSystem = .localeDefault
    @State private var showSearch = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let data = model.data {
                        loadedContent(data)
                    } else {
                        placeholder
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(model.place?.name ?? "Then & Now")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await model.useCurrentLocation(units: units) }
                    } label: {
                        Image(systemName: "location")
                    }
                    .accessibilityLabel("Use current location")

                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search city")

                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await model.refresh(units: units) }
            .task {
                if case .idle = model.loadState { await model.refresh(units: units) }
            }
            .sheet(isPresented: $showSearch) {
                CitySearchView { place in
                    showSearch = false
                    model.select(place)
                    Task { await model.refresh(units: units) }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                // Pick up a newly added key without a manual refresh.
                if case .needsKey = model.summaryState {
                    Task { await model.summarize(units: units) }
                }
            }) {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch model.loadState {
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load weather", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.refresh(units: units) } }
                Button("Search for a city") { showSearch = true }
            }
            .padding(.top, 60)
        default:
            VStack(spacing: 12) {
                ProgressView()
                Text("Looking back five years…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 120)
        }
    }

    @ViewBuilder
    private func loadedContent(_ data: ComparisonData) -> some View {
        if case .loading = model.loadState {
            ProgressView().frame(maxWidth: .infinity)
        }
        if case .failed(let message) = model.loadState {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        TodayHeaderView(data: data, units: units)

        AISummaryCard(
            state: model.summaryState,
            onRetry: { Task { await model.summarize(units: units) } },
            onAddKey: { showSettings = true }
        )

        Card(title: "Same day, last 5 years", systemImage: "chart.bar.xaxis") {
            ComparisonChartView(data: data, units: units)
        }

        Card(title: "Year by year", systemImage: "calendar") {
            VStack(spacing: 0) {
                ForEach(Array(data.all.reversed().enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 { Divider() }
                    YearRowView(snapshot: snapshot, units: units, hour: data.localHour,
                                isLastYear: snapshot.year == data.lastYear?.year)
                }
            }
        }

        Text("Weather data: Open-Meteo (ERA5 reanalysis for past years). Today's later hours are forecast.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// Rounded card container used across the screen.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
