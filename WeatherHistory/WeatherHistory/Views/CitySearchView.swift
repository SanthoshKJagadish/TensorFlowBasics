import SwiftUI

struct CitySearchView: View {
    let onSelect: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [GeocodingResponse.Result] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
                ForEach(results) { result in
                    Button {
                        onSelect(result.place)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(result.name).foregroundStyle(.primary)
                            if let detail = result.place.detail, !detail.isEmpty {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search for a city", systemImage: "magnifyingglass")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City name")
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 2 else { results = []; return }
                try? await Task.sleep(for: .milliseconds(300)) // debounce typing
                guard !Task.isCancelled else { return }
                do {
                    results = try await WeatherService().searchCities(trimmed)
                    errorMessage = nil
                } catch is CancellationError {
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .navigationTitle("Choose City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
