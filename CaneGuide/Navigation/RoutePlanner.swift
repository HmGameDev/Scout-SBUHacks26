import CoreLocation
import MapKit

/// Finds a walking route with Apple Maps and announces each turn as the person approaches it.
@MainActor
final class RoutePlanner: NSObject, CLLocationManagerDelegate {
    /// Spoken route directions.
    var onInstruction: ((String) -> Void)?
    /// Short status for the screen ("Searching…", errors).
    var onStatus: ((String) -> Void)?
    /// The route to draw on the map; nil when navigation ends.
    var onRoute: ((MKRoute?) -> Void)?

    private let locationManager = CLLocationManager()
    private var steps: [MKRoute.Step] = []
    private var stepIndex = 0
    private var announcedNextTurn = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func navigate(to query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        locationManager.startUpdatingLocation()
        onStatus?("Searching for \(query)…")

        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = query
        if let here = locationManager.location?.coordinate {
            search.region = MKCoordinateRegion(center: here, latitudinalMeters: 5000, longitudinalMeters: 5000)
        }

        do {
            guard let destination = try await MKLocalSearch(request: search).start().mapItems.first else {
                fail("No place found for \(query).")
                return
            }
            let request = MKDirections.Request()
            request.source = .forCurrentLocation()
            request.destination = destination
            request.transportType = .walking
            guard let route = try await MKDirections(request: request).calculate().routes.first else {
                fail("No walking route found.")
                return
            }

            steps = route.steps.filter { !$0.instructions.isEmpty }
            stepIndex = 0
            announcedNextTurn = false
            let name = destination.name ?? query
            let first = steps.first.map { " \($0.instructions)." } ?? ""
            onRoute?(route)
            onStatus?("Walking to \(name)")
            onInstruction?("Route to \(name), \(Self.spoken(route.distance)).\(first)")
        } catch {
            fail("Couldn't get directions. Check the internet connection.")
        }
    }

    func stopNavigation() {
        steps = []
        locationManager.stopUpdatingLocation()
        onRoute?(nil)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handle(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func handle(_ location: CLLocation) {
        guard !steps.isEmpty, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else { return }

        let nextIndex = stepIndex + 1
        guard nextIndex < steps.count else {
            // On the last step: watch for the destination.
            if let end = steps.last?.polyline.coordinates.last,
               location.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) < Tuning.arrivedDistance {
                onInstruction?("You have arrived.")
                onStatus?("Arrived")
                stopNavigation()
            }
            return
        }

        // A step's instruction describes the turn at its start, which is where the previous step ends.
        guard let turn = steps[nextIndex].polyline.coordinates.first else { return }
        let distance = location.distance(from: CLLocation(latitude: turn.latitude, longitude: turn.longitude))
        if distance < Tuning.announceTurnDistance && !announcedNextTurn {
            announcedNextTurn = true
            onInstruction?("In \(Self.spoken(distance)), \(steps[nextIndex].instructions).")
        }
        if distance < Tuning.reachedStepDistance {
            stepIndex = nextIndex
            announcedNextTurn = false
        }
    }

    private func fail(_ message: String) {
        onStatus?(message)
        onInstruction?(message)
    }

    private static func spoken(_ meters: CLLocationDistance) -> String {
        let rounded = max(5, Int((meters / 5).rounded()) * 5)
        return "\(rounded) meters"
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var result = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&result, range: NSRange(location: 0, length: pointCount))
        return result
    }
}
