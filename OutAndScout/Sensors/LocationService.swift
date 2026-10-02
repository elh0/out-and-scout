import CoreLocation
import Observation
import UIKit

/// Location, compass heading and reverse geocoding for scene names.
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var location: CLLocation?
    /// Degrees from true north the camera faces. nil until the compass settles.
    private(set) var heading: Double?
    /// The compass's own error estimate, degrees.
    private(set) var headingAccuracy: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isPrecise = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    /// Used when there's no fix, so the sun still makes sense. Central London.
    static let fallback = CLLocationCoordinate2D(latitude: 51.5072, longitude: -0.1276)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
        authorization = manager.authorizationStatus
    }

    var coordinate: CLLocationCoordinate2D { location?.coordinate ?? Self.fallback }
    var hasFix: Bool { location != nil }

    func request(_ choice: LocationChoice) {
        switch choice {
        case .precise, .approximate:
            manager.desiredAccuracy = choice == .precise ? kCLLocationAccuracyBest : kCLLocationAccuracyReduced
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                start()
            }
        case .notNow:
            break
        }
    }

    /// Starts updates if already allowed. Safe to call on every launch.
    func start() {
        // The compass doesn't need location permission, so north works from first launch.
        // Without a location fix the heading is magnetic rather than true north.
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    /// Heading is reported relative to the top of the interface, so tell Core Location
    /// which way up the phone is. The app is landscape only.
    func setInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        // UIInterfaceOrientation.landscapeRight == home edge on the right == CLDeviceOrientation.landscapeLeft
        switch orientation {
        case .portrait: manager.headingOrientation = .portrait
        case .landscapeLeft: manager.headingOrientation = .landscapeRight
        default: manager.headingOrientation = .landscapeLeft
        }
    }

    /// "brick lane, e1" for precise, "shoreditch" for approximate.
    func placeLabel(for location: CLLocation) async -> (label: String?, postcode: String?) {
        guard let mark = try? await geocoder.reverseGeocodeLocation(location).first else { return (nil, nil) }
        let district = mark.postalCode?.split(separator: " ").first.map(String.init)
        if isPrecise, let street = mark.thoroughfare {
            return ([street, district].compactMap { $0 }.joined(separator: ", "), mark.postalCode)
        }
        return (mark.subLocality ?? mark.locality, nil)
    }

    /// Street, landmark and area for the Name-this-scene card.
    func nameSuggestions() async -> [String] {
        guard let location, let mark = try? await geocoder.reverseGeocodeLocation(location).first else { return [] }
        var out: [String] = []
        if isPrecise, let street = mark.thoroughfare { out.append(street) }
        if let landmark = mark.areasOfInterest?.first { out.append(landmark) }
        if let area = mark.subLocality ?? mark.locality { out.append(area) }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    func shotLocation() async -> ShotLocation? {
        guard let location else { return nil }
        let place = await placeLabel(for: location)
        return ShotLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            label: place.label,
            postcode: place.postcode
        )
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let precise = manager.accuracyAuthorization == .fullAccuracy
        Task { @MainActor in
            self.authorization = status
            self.isPrecise = precise
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.location = last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        guard accuracy >= 0 else { return }
        Task { @MainActor in
            self.heading = value
            self.headingAccuracy = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
