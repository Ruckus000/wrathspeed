import CoreLocation
import HealthKit
import WrathspeedCore

@MainActor
protocol WorkoutRouteRecording: AnyObject {
    func begin(for location: RunLocation)
    func stop()
    func setRecording(_ isRecording: Bool)
    func finish(for workout: HKWorkout) async throws -> [RoutePoint]
}

enum RouteLocationAction: Equatable {
    case requestWhenInUse
    case requestAlways
    case start(allowsBackground: Bool)
    case stop
}

enum RouteLocationPolicy {
    static func action(
        authorization: CLAuthorizationStatus,
        isOutdoorWorkout: Bool,
        isRecording: Bool,
        requestedAlwaysAuthorization: Bool
    ) -> RouteLocationAction {
        guard isOutdoorWorkout, isRecording else { return .stop }
        switch authorization {
        case .notDetermined: return .requestWhenInUse
        case .authorizedWhenInUse:
            #if os(iOS)
            return requestedAlwaysAuthorization ? .start(allowsBackground: false) : .requestAlways
            #else
            return .start(allowsBackground: false)
            #endif
        case .authorizedAlways: return .start(allowsBackground: true)
        case .denied, .restricted: return .stop
        @unknown default: return .stop
        }
    }
}

@MainActor
final class WorkoutRouteRecorder: NSObject, CLLocationManagerDelegate, WorkoutRouteRecording {
    private let healthStore: HKHealthStore
    private let locationManager = CLLocationManager()
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locations: [CLLocation] = []
    private var isRecording = false
    private var isOutdoorWorkout = false
    private var isUpdatingLocation = false
    private var requestedAlwaysAuthorization = false

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func begin(for location: RunLocation) {
        locations = []
        routeBuilder = nil
        isRecording = false
        isOutdoorWorkout = location == .outdoor
        requestedAlwaysAuthorization = false
        guard isOutdoorWorkout else { return }
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        isRecording = true
        configureAuthorizationAndStartIfPossible()
    }

    func stop() {
        isRecording = false
        isOutdoorWorkout = false
        stopLocationUpdates()
    }

    func setRecording(_ isRecording: Bool) {
        self.isRecording = isRecording
        guard isOutdoorWorkout else { return }
        if isRecording {
            configureAuthorizationAndStartIfPossible()
        } else {
            stopLocationUpdates()
        }
    }

    func finish(for workout: HKWorkout) async throws -> [RoutePoint] {
        defer {
            routeBuilder = nil
            locations = []
        }
        guard let routeBuilder, !locations.isEmpty else { return [] }
        try await insert(locations, into: routeBuilder)
        try await complete(routeBuilder, for: workout)
        return locations.map {
            RoutePoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, timestamp: $0.timestamp)
        }
    }

    private func insert(_ locations: [CLLocation], into builder: HKWorkoutRouteBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.insertRouteData(locations) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: HKError(.errorHealthDataUnavailable)) }
            }
        }
    }

    private func complete(_ builder: HKWorkoutRouteBuilder, for workout: HKWorkout) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.finishRoute(with: workout, metadata: nil) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func configureAuthorizationAndStartIfPossible() {
        let action = RouteLocationPolicy.action(
            authorization: locationManager.authorizationStatus,
            isOutdoorWorkout: isOutdoorWorkout,
            isRecording: isRecording,
            requestedAlwaysAuthorization: requestedAlwaysAuthorization
        )
        switch action {
        case .requestWhenInUse:
            locationManager.requestWhenInUseAuthorization()
        case .requestAlways:
            #if os(iOS)
            requestedAlwaysAuthorization = true
            locationManager.requestAlwaysAuthorization()
            #endif
            startLocationUpdates(allowsBackground: false)
        case let .start(allowsBackground):
            startLocationUpdates(allowsBackground: allowsBackground)
        case .stop:
            stopLocationUpdates()
        }
    }

    private func startLocationUpdates(allowsBackground: Bool) {
        guard isRecording, !isUpdatingLocation else { return }
        #if os(iOS)
        locationManager.allowsBackgroundLocationUpdates = allowsBackground
        locationManager.showsBackgroundLocationIndicator = allowsBackground
        #endif
        locationManager.startUpdatingLocation()
        isUpdatingLocation = true
    }

    private func stopLocationUpdates() {
        if isUpdatingLocation {
            locationManager.stopUpdatingLocation()
            isUpdatingLocation = false
        }
        #if os(iOS)
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        #endif
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.isOutdoorWorkout, self.isRecording else { return }
            self.configureAuthorizationAndStartIfPossible()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard self.isRecording else { return }
            self.locations.append(contentsOf: locations.filter { $0.horizontalAccuracy >= 0 })
        }
    }
}
