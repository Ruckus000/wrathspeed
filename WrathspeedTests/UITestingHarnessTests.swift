import SwiftData
import XCTest
@testable import Wrathspeed
@testable import WrathspeedCore

final class UITestingHarnessTests: XCTestCase {
    func testUITestingSupportResetArgumentIsDebugOnlyContract() {
        XCTAssertEqual(UITestingSupport.resetStoreLaunchArgument, "-uiTestingResetStore")
    }

    func testPersistenceResetClearsStoredSnapshot() throws {
        let container = try ModelContainer(
            for: SnapshotEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        var state = PersistedState.initial
        state.hasOnboarded = true
        state.profile = RunnerProfile(
            ability: .intermediate,
            daysPerWeek: 4,
            longRunWeekday: .saturday,
            unit: .kilometers
        )
        try Persistence.save(state, to: context)
        XCTAssertTrue(try Persistence.load(from: context).hasOnboarded)

        try Persistence.reset(from: context)
        XCTAssertFalse(try Persistence.load(from: context).hasOnboarded)
    }

    @MainActor
    func testAttachWithResetStoreIgnoresPersistedOnboardingState() throws {
        let container = try ModelContainer(
            for: SnapshotEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        var state = PersistedState.initial
        state.hasOnboarded = true
        try Persistence.save(state, to: context)

        let store = AppStore()
        store.attach(context: context, resetStore: true)

        XCTAssertFalse(store.hasOnboarded)
        XCTAssertNil(store.profile)
        XCTAssertNil(store.plan)
    }
}
