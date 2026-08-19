import Foundation
import SwiftData
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

final class OnboardingFlowTests: XCTestCase {
    func testImperialAndMetricProduceEquivalentStoredMeters() throws {
        let catalog = try makeCatalog()
        let imperial = OnboardingInputs(
            goalMode: .distance,
            goalKind: .tenK,
            weekCount: 10,
            unit: .miles,
            weeklyDisplayDistance: 25,
            longestDisplayDistance: 8,
            availableDays: [.tuesday, .thursday, .saturday, .sunday],
            longRunDay: .sunday,
            strengthEnabled: false
        )
        var metric = imperial
        metric.unit = .kilometers
        metric.weeklyDisplayDistance = 40
        metric.longestDisplayDistance = 13

        let imperialProfile = try OnboardingDraftBuilder.build(inputs: imperial, catalog: catalog).plan.profile
        let metricProfile = try OnboardingDraftBuilder.build(inputs: metric, catalog: catalog).plan.profile

        XCTAssertEqual(imperialProfile.weeklyMileageMeters, metricProfile.weeklyMileageMeters, accuracy: 1_500)
        XCTAssertEqual(imperialProfile.longestRunMeters, metricProfile.longestRunMeters, accuracy: 500)
    }

    func testRecentPerformanceChangesVDOT() throws {
        let catalog = try makeCatalog()
        let withRace = OnboardingInputs(
            goalMode: .distance,
            goalKind: .tenK,
            weekCount: 10,
            unit: .kilometers,
            ability: .intermediate,
            weeklyDisplayDistance: 40,
            longestDisplayDistance: 12,
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday,
            includesRecentPerformance: true,
            recentDistanceDisplay: 10,
            recentDurationMinutes: 40,
            recentDurationSeconds: 0,
            strengthEnabled: false
        )
        var estimate = withRace
        estimate.includesRecentPerformance = false

        let raceDraft = try OnboardingDraftBuilder.build(inputs: withRace, catalog: catalog)
        let estimateDraft = try OnboardingDraftBuilder.build(inputs: estimate, catalog: catalog)

        XCTAssertEqual(raceDraft.vdotSource, .recentPerformance)
        XCTAssertEqual(estimateDraft.vdotSource, .abilityEstimate)
        XCTAssertGreaterThan(raceDraft.plan.profile.vdot, estimateDraft.plan.profile.vdot)
        XCTAssertNotEqual(
            raceDraft.zones.secondsPerKilometer(for: .easy),
            estimateDraft.zones.secondsPerKilometer(for: .easy)
        )
    }

    func testLongRunMustBeAvailableDay() {
        let inputs = OnboardingInputs(
            availableDays: [.monday, .wednesday, .friday],
            longRunDay: .saturday
        )
        XCTAssertThrowsError(try OnboardingValidator.validate(inputs)) { error in
            XCTAssertEqual(error as? OnboardingValidationError, .longRunNotAvailable)
        }
    }

    func testRaceDateTooSoonBlocked() {
        let inputs = OnboardingInputs(
            goalMode: .race,
            goalKind: .marathon,
            raceDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
            availableDays: [.tuesday, .thursday, .saturday, .sunday],
            longRunDay: .sunday,
            strengthEnabled: false
        )
        XCTAssertThrowsError(try OnboardingValidator.validate(inputs)) { error in
            guard case PlanInputError.raceDateTooSoon = error else {
                return XCTFail("Expected raceDateTooSoon, got \(error)")
            }
        }
    }

    @MainActor
    func testDraftPreviewDoesNotMarkOnboardedOrPersistPlan() throws {
        let catalog = try makeCatalog()
        let container = try ModelContainer(
            for: Schema([
                SnapshotEntity.self,
                MigrationMarkerEntity.self,
                AppSettingsEntity.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = AppStore(strengthCatalogLoader: { catalog })
        store.attach(context: ModelContext(container))

        let inputs = OnboardingInputs(
            goalMode: .distance,
            goalKind: .fiveK,
            weekCount: 8,
            unit: .kilometers,
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday,
            strengthEnabled: false
        )
        let draft = try store.generateOnboardingDraft(from: inputs)

        XCTAssertFalse(store.hasOnboarded)
        XCTAssertNil(store.plan)
        XCTAssertEqual(store.onboardingDraft?.plan.id, draft.plan.id)
    }

    @MainActor
    func testPersistenceFailureDoesNotEnterTabs() throws {
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
        let context = ModelContext(container)
        let store = AppStore(strengthCatalogLoader: { catalog })
        store.attach(context: context)
        store.setForceSaveFailureForTesting(true)

        let inputs = OnboardingInputs(
            goalMode: .distance,
            goalKind: .fiveK,
            weekCount: 8,
            unit: .kilometers,
            availableDays: [.monday, .wednesday, .friday, .sunday],
            longRunDay: .sunday,
            strengthEnabled: false
        )
        let draft = try store.generateOnboardingDraft(from: inputs)

        store.confirmOnboarding(draft: draft)

        XCTAssertFalse(store.hasOnboarded)
        XCTAssertNil(store.plan)
        XCTAssertNotNil(store.errorMessage)
    }

    private func makeCatalog() throws -> StrengthCatalog {
        let json = """
        {"exercises":[
          {"id":"squat","name":"Squat","focus":["legsCore","fullBody"],"equipment":["bodyweight"],"symbolName":"figure.strengthtraining.traditional","defaultReps":10,"cue":"Sit back."}
        ]}
        """
        return try JSONDecoder().decode(StrengthCatalog.self, from: Data(json.utf8))
    }
}
