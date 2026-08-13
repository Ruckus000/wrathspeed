import CoreLocation
import Foundation
import SwiftData
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

final class CoachingMVPHardeningTests: XCTestCase {
    func testCapabilitiesDeclareHealthKitAndBackgroundLocationCopy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for relativePath in ["Wrathspeed/Wrathspeed.entitlements", "WrathspeedWatch/WrathspeedWatch.entitlements"] {
            let data = try Data(contentsOf: root.appending(path: relativePath))
            let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(plist["com.apple.developer.healthkit"] as? Bool, true)
        }
        let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription"))
    }

    func testRoutePolicyUsesNoLocationForTreadmillAndEscalatesOutdoorAuthorization() {
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedAlways,
                isOutdoorWorkout: false,
                isRecording: true,
                requestedAlwaysAuthorization: false
            ),
            .stop
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .notDetermined,
                isOutdoorWorkout: true,
                isRecording: true,
                requestedAlwaysAuthorization: false
            ),
            .requestWhenInUse
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedWhenInUse,
                isOutdoorWorkout: true,
                isRecording: true,
                requestedAlwaysAuthorization: false
            ),
            .requestAlways
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedAlways,
                isOutdoorWorkout: true,
                isRecording: true,
                requestedAlwaysAuthorization: true
            ),
            .start(allowsBackground: true)
        )
        XCTAssertEqual(
            RouteLocationPolicy.action(
                authorization: .authorizedAlways,
                isOutdoorWorkout: true,
                isRecording: false,
                requestedAlwaysAuthorization: true
            ),
            .stop
        )
    }

    func testWatchStartResolverHandlesEitherArrivalOrderAndDuplicates() {
        let request = makeStartRequest()

        var blueprintFirst = WatchStartResolver()
        XCTAssertNil(blueprintFirst.receive(request))
        XCTAssertEqual(blueprintFirst.receiveLaunchRequest()?.id, request.id)
        XCTAssertNil(blueprintFirst.receive(request))
        XCTAssertNil(blueprintFirst.receiveLaunchRequest())

        var launchFirst = WatchStartResolver()
        XCTAssertNil(launchFirst.receiveLaunchRequest())
        XCTAssertEqual(launchFirst.receive(request)?.id, request.id)

        var missingBlueprint = WatchStartResolver()
        XCTAssertNil(missingBlueprint.receiveLaunchRequest())
        XCTAssertNil(missingBlueprint.receiveLaunchRequest())
    }

    func testRouteSamplingCapsPointsAndPreservesEndpoints() {
        let points = (0..<1_000).map {
            RoutePoint(latitude: Double($0), longitude: Double(-$0), timestamp: Date(timeIntervalSince1970: Double($0)))
        }
        let sampled = RouteSampler.displayRoute(from: points, limit: 100)
        XCTAssertEqual(sampled.count, 100)
        XCTAssertEqual(sampled.first, points.first)
        XCTAssertEqual(sampled.last, points.last)
    }

    @MainActor
    func testStrengthPreferenceUpdatePreservesPastAndRunningPlanAndPersists() throws {
        let catalog = try makeCatalog()
        let container = try ModelContainer(
            for: Schema([
                SnapshotEntity.self,
                MigrationMarkerEntity.self,
                AppSettingsEntity.self,
                TrainingPlanEntity.self,
                ScheduledWorkoutEntity.self,
                WorkoutResultEntity.self,
                StrengthSessionEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(strengthCatalogLoader: { catalog })
        store.attach(context: ModelContext(container))

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let profile = RunnerProfile(
            ability: .intermediate,
            daysPerWeek: 4,
            longRunWeekday: .saturday,
            unit: .kilometers
        )
        let run = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: calendar.date(byAdding: .day, value: 28, to: today)!,
            kind: .easy,
            title: "Easy run",
            steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        let plan = TrainingPlan(goal: TrainingGoal(kind: .fiveK, weekCount: 8), profile: profile, workouts: [run])
        store.profile = profile
        store.plan = plan

        let existing = StrengthPlanner.schedule(
            preferences: StrengthPreferences(),
            startDate: calendar.date(byAdding: .day, value: -14, to: today)!,
            weekCount: 4,
            calendar: calendar,
            catalog: catalog
        )
        store.strengthSessions = existing
        let pastIDs = Set(existing.filter { $0.date < today }.map(\.id))

        let updated = StrengthPreferences(
            ability: .advanced,
            goal: .allRound,
            durationMinutes: 60,
            sessionsPerWeek: 3,
            preferredDays: [.tuesday, .thursday, .saturday],
            equipment: [.bodyweight, .dumbbell]
        )
        store.updateStrengthPreferences(updated)

        XCTAssertEqual(store.strengthPrefs, updated)
        XCTAssertEqual(store.plan, plan)
        XCTAssertEqual(Set(store.strengthSessions.filter { $0.date < today }.map(\.id)), pastIDs)
        XCTAssertTrue(store.strengthSessions.filter { $0.date >= today }.allSatisfy { $0.durationMinutes == 60 })

        let restored = AppStore(strengthCatalogLoader: { catalog })
        restored.attach(context: ModelContext(container))
        XCTAssertEqual(restored.strengthPrefs, updated)
        XCTAssertEqual(restored.plan?.id, plan.id)
        XCTAssertEqual(restored.plan?.goal, plan.goal)
        XCTAssertEqual(restored.plan?.workouts, plan.workouts)
        XCTAssertEqual(restored.strengthSessions, store.strengthSessions)
    }

    @MainActor
    func testStrengthPreferenceUpdateIsAtomicWhenCatalogLoadingFails() {
        enum FixtureError: Error { case unavailable }
        let store = AppStore(strengthCatalogLoader: { throw FixtureError.unavailable })
        let original = store.strengthPrefs
        let profile = RunnerProfile(
            ability: .beginner,
            daysPerWeek: 3,
            longRunWeekday: .saturday,
            unit: .kilometers
        )
        let run = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Date().addingTimeInterval(7 * 86_400),
            kind: .easy,
            title: "Easy run",
            steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        store.plan = TrainingPlan(goal: TrainingGoal(kind: .fiveK), profile: profile, workouts: [run])

        var requested = original
        requested.durationMinutes = 60
        store.updateStrengthPreferences(requested)

        XCTAssertEqual(store.strengthPrefs, original)
        XCTAssertNotNil(store.errorMessage)
    }

    private func makeStartRequest() -> WatchStartRequest {
        WatchStartRequest(
            blueprint: WorkoutBlueprint(
                date: Date(),
                kind: .easy,
                title: "Easy run",
                steps: [WorkoutStep(name: "Easy", target: .distance(meters: 5_000), intensity: .zone(.easy))],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            ),
            vdot: 45
        )
    }

    private func makeCatalog() throws -> StrengthCatalog {
        let json = """
        {"exercises":[
          {"id":"squat","name":"Squat","focus":["legsCore","fullBody"],"equipment":["bodyweight","dumbbell"],"symbolName":"figure.strengthtraining.traditional","defaultReps":10,"cue":"Sit back."},
          {"id":"plank","name":"Plank","focus":["legsCore","fullBody"],"equipment":["bodyweight"],"symbolName":"figure.core.training","defaultReps":10,"cue":"Brace."},
          {"id":"pushup","name":"Push-up","focus":["upper","fullBody"],"equipment":["bodyweight"],"symbolName":"figure.strengthtraining.functional","defaultReps":10,"cue":"Stay tall."}
        ]}
        """
        return try JSONDecoder().decode(StrengthCatalog.self, from: Data(json.utf8))
    }
}
