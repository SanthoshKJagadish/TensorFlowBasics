import CoreLocation

enum LocationError: LocalizedError {
    case denied
    case busy

    var errorDescription: String? {
        switch self {
        case .denied: return "Location access is off. Search for a city instead, or enable location in Settings."
        case .busy: return "Already looking up your location."
        }
    }
}

/// One-shot async wrapper around CLLocationManager.
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentPlace() async throws -> Place {
        let location = try await requestLocation()
        var name = "Current Location"
        var detail: String?
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            name = placemark.locality ?? placemark.name ?? name
            detail = [placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", ")
        }
        return Place(name: name, detail: detail,
                     latitude: location.coordinate.latitude,
                     longitude: location.coordinate.longitude)
    }

    private func requestLocation() async throws -> CLLocation {
        guard continuation == nil else { throw LocationError.busy }
        switch manager.authorizationStatus {
        case .denied, .restricted: throw LocationError.denied
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(.failure(LocationError.denied))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
