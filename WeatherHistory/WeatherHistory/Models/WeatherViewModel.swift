import Foundation
import Observation

@MainActor
@Observable
final class WeatherViewModel {
    enum LoadState {
        case idle
        case loading
        case loaded(ComparisonData)
        case failed(String)
    }

    enum SummaryState {
        case idle
        case needsKey
        case loading
        case loaded(WeatherSummary)
        case failed(String)
    }

    private(set) var place: Place?
    private(set) var loadState: LoadState = .idle
    private(set) var summaryState: SummaryState = .idle
    /// Keeps the last good data visible while refreshing.
    private(set) var data: ComparisonData?

    private let weather = WeatherService()
    private let locationManager = LocationManager()
    private static let placeKey = "lastPlace"

    init() {
        if let saved = UserDefaults.standard.data(forKey: Self.placeKey),
           let place = try? JSONDecoder().decode(Place.self, from: saved) {
            self.place = place
        }
    }

    func refresh(units: UnitSystem) async {
        guard let place else {
            await useCurrentLocation(units: units)
            return
        }
        loadState = .loading
        do {
            let result = try await weather.fetchComparison(for: place)
            data = result
            loadState = .loaded(result)
            await summarize(units: units)
        } catch is CancellationError {
            loadState = data.map(LoadState.loaded) ?? .idle
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func useCurrentLocation(units: UnitSystem) async {
        loadState = .loading
        do {
            let place = try await locationManager.currentPlace()
            select(place)
            await refresh(units: units)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func select(_ place: Place) {
        self.place = place
        data = nil
        summaryState = .idle
        if let encoded = try? JSONEncoder().encode(place) {
            UserDefaults.standard.set(encoded, forKey: Self.placeKey)
        }
    }

    func summarize(units: UnitSystem) async {
        guard let data else { return }
        guard let key = KeychainStore.loadAPIKey() else {
            summaryState = .needsKey
            return
        }
        summaryState = .loading
        do {
            let summary = try await ClaudeService(apiKey: key).summarize(data, units: units)
            summaryState = .loaded(summary)
        } catch {
            summaryState = .failed(error.localizedDescription)
        }
    }
}
