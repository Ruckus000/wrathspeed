import SwiftData
import XCTest
@testable import Wrathspeed
import WrathspeedCore

@MainActor
final class PlanMutationTests: XCTestCase {
    private let modelTypes: [any PersistentModel.Type] = [
        SnapshotEntity.self,
        MigrationMarkerEntity.self,
        AppSettingsEntity.self,
        TrainingPlanEntity.self,
        ScheduledWorkoutEntity.self,
        WorkoutResultEntity.self,
        StrengthSessionEntity.self,
        StrengthSessionResultEntity.self,
        MobilitySessionResultEntity.self,
        PlanChangeEntity.self,
        ActiveSessionSnapshotEntity.self,
    ]

    private func makeStore(reminder: MockWorkoutReminderScheduler = MockWorkoutReminderScheduler()) throws -> (AppStore, ModelContext) {
        let container = try ModelContainer(for: Schema(modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = AppStore(reminderScheduler: reminder)
        store.attach(context: context)
        return (store, context)
    }

    private func planChangeCount(_ context: ModelContext) -> Int {
        (try? context.fetch(FetchDescriptor<PlanChangeEntity>()).count) ?? 0
    }

    private func samplePlan(workoutDate: Date = Date()) -> TrainingPlan {
        let easy = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: workoutDate,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        return TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [easy]
        )
    }

    func testSkipWritesOnePlanChangeAndPublishesAfterPersist() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let watchBefore = store.watchPublicationCountForTesting

        store.skip(workout)
        XCTAssertEqual(planChangeCount(context), 1)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore + 1)
    }

    func testStaleSkipIsIdempotent() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        store.skip(workout)
        let afterFirst = planChangeCount(context)
        let skipped = try XCTUnwrap(store.plan?.workouts.first(where: { $0.id == workout.id }))
        store.skip(skipped)
        XCTAssertEqual(planChangeCount(context), afterFirst)
    }

    func testMovePersistsAndSurvivesRelaunch() throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, context) = try makeStore(reminder: reminder)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)

        store.move(workout, to: tomorrow, scheduledTimeMinutes: 480, reminderEnabled: true)
        XCTAssertEqual(store.plan?.workouts.first?.scheduledTimeMinutes, 480)
        XCTAssertTrue(store.plan?.workouts.first?.reminderEnabled == true)

        let restored = AppStore(reminderScheduler: reminder)
        restored.attach(context: context)
        XCTAssertEqual(restored.plan?.workouts.first?.blueprint.date, Calendar.current.startOfDay(for: tomorrow))
        XCTAssertEqual(restored.plan?.workouts.first?.scheduledTimeMinutes, 480)
    }

    func testPersistFailureRestoresMemoryAndSkipsWatchPublication() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let originalDate = workout.date
        let watchBefore = store.watchPublicationCountForTesting

        store.setForceSaveFailureAfterMutationForTesting(true)
        store.move(workout, to: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)
        XCTAssertEqual(store.plan?.workouts.first?.date, originalDate)
        XCTAssertEqual(planChangeCount(context), 0)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore)
    }

    func testUndoRestoresOriginalPlan() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let target = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        store.move(workout, to: target)
        store.undoLastPlanChange()
        XCTAssertEqual(store.plan?.workouts.first?.date, workout.date)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testFailedUndoLeavesMutatedState() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let target = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
        store.move(workout, to: target)
        store.setForceSaveFailureAfterMutationForTesting(true)
        store.undoLastPlanChange()
        XCTAssertEqual(store.plan?.workouts.first?.blueprint.date, Calendar.current.startOfDay(for: target))
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testNotFeeling100OverlayPreservesBasePlan() throws {
        let (store, _) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        let quality = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            kind: .tempo,
            title: "Tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        store.plan?.workouts.append(quality)
        store.save()

        store.applyNotFeeling100(N100Adjustment(start: Date(), dayCount: 7, mode: .reducedDifficulty, returnPace: .balanced))
        XCTAssertEqual(store.plan?.workouts.last?.blueprint.kind, .tempo)
        XCTAssertEqual(store.displayPlan?.workouts.last?.blueprint.kind, .easy)
        store.endNotFeeling100()
        XCTAssertEqual(store.displayPlan?.workouts.last?.blueprint.kind, .tempo)
    }

    func testConvertWritesOnePlanChange() throws {
        let (store, context) = try makeStore()
        let quality = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Date(),
            kind: .tempo,
            title: "Tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [quality]
        )
        store.profile = store.plan?.profile
        store.save()
        store.skip(quality, convertQuality: true)
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testPlanChangeFailureCommitsNeitherPlanNorChange() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let originalStatus = workout.status
        store.setForcePlanChangeFailureForTesting(true)
        store.skip(workout)
        XCTAssertEqual(store.plan?.workouts.first?.status, originalStatus)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testFailedMutationSurvivesRelaunch() throws {
        let container = try ModelContainer(for: Schema(modelTypes), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = AppStore()
        store.attach(context: context)
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let originalDate = workout.date
        store.setForcePlanChangeFailureForTesting(true)
        store.move(workout, to: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)

        let reloaded = AppStore()
        reloaded.attach(context: context)
        XCTAssertTrue(Calendar.current.isDate(
            reloaded.plan?.workouts.first?.date ?? .distantPast,
            inSameDayAs: originalDate
        ))
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testRetryAfterFailureCreatesOneChange() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        store.setForcePlanChangeFailureForTesting(true)
        store.skip(workout)
        store.setForcePlanChangeFailureForTesting(false)
        let skipped = try XCTUnwrap(store.plan?.workouts.first)
        store.skip(skipped)
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testSuccessToastOnlyAfterAtomicCommit() throws {
        let (store, _) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        store.setForcePlanChangeFailureForTesting(true)
        store.skip(workout)
        XCTAssertNil(store.toastMessage)
        store.setForcePlanChangeFailureForTesting(false)
        let scheduled = try XCTUnwrap(store.plan?.workouts.first)
        let watchBefore = store.watchPublicationCountForTesting
        store.skip(scheduled)
        XCTAssertNotNil(store.toastMessage)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore + 1)
    }

    func testCoachProposalAppliesAtomicallyPublishesAndUndoRestoresExactState() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let originalPlan = try XCTUnwrap(store.plan)
        let originalProfile = try XCTUnwrap(store.profile)
        let workout = try XCTUnwrap(originalPlan.workouts.first)
        let watchBefore = store.watchPublicationCountForTesting

        let proposal = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(proposal.changes.count, 1)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)
        XCTAssertEqual(planChangeCount(context), 1)
        XCTAssertEqual(store.watchPublicationCountForTesting, watchBefore + 1)
        XCTAssertEqual(store.plan?.workouts.first?.blueprint.location, .treadmill)

        store.undoLastPlanChange()
        XCTAssertEqual(store.plan, originalPlan)
        XCTAssertEqual(store.profile, originalProfile)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachSorenessAppliesMultipleEditsAsOneUndoableTransaction() throws {
        let (store, context) = try makeStore()
        let today = Date()
        let quality = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: today,
            kind: .tempo,
            title: "Tempo",
            steps: [WorkoutStep(name: "Tempo", target: .distance(meters: 8_000), intensity: .zone(.threshold))],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ))
        let longRun = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: today,
            kind: .longRun,
            title: "Long run",
            steps: [WorkoutStep(name: "Long run", target: .distance(meters: 12_000), intensity: .zone(.easy))],
            plannedDistanceMeters: 12_000,
            usesPaceTargets: true
        ))
        store.plan = samplePlan()
        store.plan?.workouts = [quality, longRun]
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)

        let proposal = store.previewCoachIntent(.cutIntensity)
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(proposal.changes.count, 2)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)
        XCTAssertEqual(planChangeCount(context), 1)
        XCTAssertEqual(store.plan?.workouts.first(where: { $0.id == quality.id })?.status, .convertedToEasy)
        XCTAssertEqual(
            try XCTUnwrap(store.plan?.workouts.first(where: { $0.id == longRun.id })?.blueprint.plannedDistanceMeters),
            9_600,
            accuracy: 0.01
        )

        store.undoLastPlanChange()
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalPersistsReloadsAndReconcilesReminders() async throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, context) = try makeStore(reminder: reminder)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        var easy = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: tomorrow,
            kind: .easy,
            title: "Easy",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        easy.reminderEnabled = true
        easy.scheduledTimeMinutes = 420
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [easy]
        )
        store.profile = store.plan?.profile
        store.save()

        let proposal = store.previewCoachIntent(.reshapeForTravel(travelDates: [tomorrow]))
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)
        await store.awaitReminderReconciliation()
        XCTAssertTrue(reminder.cancelled.contains(easy.id))
        XCTAssertEqual(planChangeCount(context), 1)

        let restored = AppStore(reminderScheduler: reminder)
        restored.attach(context: context)
        XCTAssertFalse(restored.plan?.workouts.contains(where: { $0.id == easy.id }) == true)
    }

    func testCoachProposalRejectsStaleSnapshotWithoutWritingAChange() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let proposal = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        store.plan?.workouts[0].blueprint.title = "Changed while reviewing"

        guard case let .rejected(reason) = store.applyCoachProposal(proposal) else {
            return XCTFail("Expected a stale proposal to be rejected")
        }
        XCTAssertTrue(reason.contains("changed"))
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalRejectsTamperedDiffWithoutMutatingPlan() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)
        let workout = try XCTUnwrap(original.workouts.first)
        var tampered = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        tampered.proposedPlan.workouts[0].blueprint.title = "Unauthorized edit"

        guard case let .rejected(reason) = store.applyCoachProposal(tampered) else {
            return XCTFail("A proposal with a forged diff must be rejected")
        }
        XCTAssertTrue(reason.contains("diff") || reason.contains("match"))
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalRejectsStableWorkoutIDTamperingWithoutMutatingPlan() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)
        let workout = try XCTUnwrap(original.workouts.first)
        var tampered = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        tampered.basePlan.workouts[0].id = UUID()

        guard case .rejected = store.applyCoachProposal(tampered) else {
            return XCTFail("A proposal with a changed stable workout ID must be rejected")
        }
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalRejectsBlueprintIdentityTamperingWithoutMutatingPlan() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)
        let workout = try XCTUnwrap(original.workouts.first)
        var tampered = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        tampered.proposedPlan.workouts[0].blueprint.id = UUID()

        guard case .rejected = store.applyCoachProposal(tampered) else {
            return XCTFail("A proposal with a changed blueprint identity must be rejected")
        }
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalRejectsDirectStepIdentityTamperingWithoutMutatingPlan() throws {
        let (store, context) = try makeStore()
        var steppedPlan = samplePlan()
        steppedPlan.workouts[0].blueprint.steps = [WorkoutStep(
            name: "Easy",
            target: .distance(meters: 5_000),
            intensity: .zone(.easy)
        )]
        store.plan = steppedPlan
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)
        let workout = try XCTUnwrap(original.workouts.first)
        var tampered = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        tampered.proposedPlan.workouts[0].blueprint.steps[0].id = UUID()

        guard case .rejected = store.applyCoachProposal(tampered) else {
            return XCTFail("A direct proposal with a changed step identity must be rejected")
        }
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalRejectsProfileAndAdjustmentTampering() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let proposal = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))

        var profileTampered = proposal
        profileTampered.proposedProfile.vdot += 1
        guard case .rejected = store.applyCoachProposal(profileTampered) else {
            return XCTFail("A proposal with mismatched profile data must be rejected")
        }
        XCTAssertEqual(planChangeCount(context), 0)

        var adjustmentTampered = proposal
        adjustmentTampered.proposedN100 = N100Adjustment(
            start: Date(),
            dayCount: 1,
            mode: .pause,
            returnPace: .balanced
        )
        guard case .rejected = store.applyCoachProposal(adjustmentTampered) else {
            return XCTFail("A proposal with mismatched adjustment data must be rejected")
        }
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachProposalRejectsForgedWarningsAndSecondApproval() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)
        let target = try XCTUnwrap(store.profile?.vdot) * 2
        var proposal = store.previewCoachIntent(.retargetVDOT(target: target))
        XCTAssertTrue(proposal.isApplicable)

        proposal.warnings = []
        guard case .rejected = store.applyCoachProposal(proposal) else {
            return XCTFail("A proposal with forged warnings must be rejected")
        }
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)

        let valid = store.previewCoachIntent(.retargetVDOT(target: target))
        XCTAssertEqual(store.applyCoachProposal(valid), .applied)
        XCTAssertEqual(planChangeCount(context), 1)
        guard case .rejected = store.applyCoachProposal(valid) else {
            return XCTFail("The same approval must not be applied twice")
        }
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testCoachProposalSupportsLongRunMoveAndPreservesCompletedHistory() throws {
        let (store, context) = try makeStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let completed = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: yesterday,
            kind: .tempo,
            title: "Completed tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ), status: .completed)
        store.plan = samplePlan()
        store.plan?.workouts.append(completed)
        store.profile = store.plan?.profile
        store.save()

        let proposal = store.previewCoachIntent(.moveLongRun(to: .saturday))
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(proposal.proposedProfile.longRunWeekday, .saturday)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)
        XCTAssertEqual(store.profile?.longRunWeekday, .saturday)
        XCTAssertEqual(store.plan?.workouts.first(where: { $0.id == completed.id }), completed)
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testCoachProposalSupportsVDOTRegenerationAndLeavesCompletedHistoryUntouched() throws {
        let (store, context) = try makeStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let completed = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: yesterday,
            kind: .tempo,
            title: "Completed tempo",
            steps: [],
            plannedDistanceMeters: 8_000,
            usesPaceTargets: true
        ), status: .completed)
        store.plan = samplePlan()
        store.plan?.workouts.append(completed)
        store.profile = store.plan?.profile
        store.save()
        let originalProfile = try XCTUnwrap(store.profile)

        let proposal = store.previewCoachIntent(.retargetVDOT(target: originalProfile.vdot * 1.02))
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)
        XCTAssertEqual(try XCTUnwrap(store.profile?.vdot), originalProfile.vdot * 1.02, accuracy: 0.0001)
        XCTAssertEqual(store.plan?.workouts.first(where: { $0.id == completed.id }), completed)
        XCTAssertEqual(planChangeCount(context), 1)
    }

    func testCoachVDOTPersistenceFailureRestoresPlanAndProfile() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let originalPlan = try XCTUnwrap(store.plan)
        let originalProfile = try XCTUnwrap(store.profile)
        let proposal = store.previewCoachIntent(.retargetVDOT(target: originalProfile.vdot * 1.02))
        XCTAssertTrue(proposal.isApplicable)

        store.setForceSaveFailureAfterMutationForTesting(true)
        guard case .rejected = store.applyCoachProposal(proposal) else {
            return XCTFail("Expected the coach persistence failure")
        }
        XCTAssertEqual(store.plan, originalPlan)
        XCTAssertEqual(store.profile, originalProfile)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachVDOTPreservesScheduledAndBlueprintIdentityAndReminderMetadata() throws {
        let reminder = MockWorkoutReminderScheduler()
        let (store, _) = try makeStore(reminder: reminder)
        var existing = samplePlan()
        existing.workouts[0].scheduledTimeMinutes = 420
        existing.workouts[0].reminderEnabled = true
        let trackedID = existing.workouts[0].id
        let trackedBlueprintID = existing.workouts[0].blueprint.id
        store.plan = existing
        store.profile = existing.profile
        store.save()

        let proposal = store.previewCoachIntent(.retargetVDOT(target: existing.profile.vdot * 1.02))
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)

        let retained = try XCTUnwrap(store.plan?.workouts.first(where: { $0.id == trackedID }))
        XCTAssertEqual(retained.blueprint.id, trackedBlueprintID)
        XCTAssertEqual(retained.scheduledTimeMinutes, 420)
        XCTAssertTrue(retained.reminderEnabled)
    }

    func testCoachLongRunMovePreservesScheduledAndBlueprintIdentityAndReminderMetadata() throws {
        let profile = RunnerProfile(
            ability: .intermediate,
            weeklyMileageMeters: 30_000,
            longestRunMeters: 10_000,
            daysPerWeek: 4,
            longRunWeekday: .sunday,
            unit: .kilometers
        )
        let goal = TrainingGoal(kind: .fiveK, weekCount: 8)
        let request = PlanRequest(goal: goal, profile: profile, startDate: Date(), calendar: .current)
        var existing = PlanGenerator.generate(request)
        let longRunIndex = try XCTUnwrap(existing.workouts.firstIndex {
            $0.blueprint.kind == .longRun && $0.date >= Calendar.current.startOfDay(for: Date())
        })
        existing.workouts[longRunIndex].scheduledTimeMinutes = 450
        existing.workouts[longRunIndex].reminderEnabled = true
        let trackedID = existing.workouts[longRunIndex].id
        let trackedBlueprintID = existing.workouts[longRunIndex].blueprint.id

        let (store, _) = try makeStore()
        store.plan = existing
        store.profile = profile
        store.save()
        let proposal = store.previewCoachIntent(.moveLongRun(to: .saturday))
        XCTAssertTrue(proposal.isApplicable)
        XCTAssertEqual(store.applyCoachProposal(proposal), .applied)

        let retained = try XCTUnwrap(store.plan?.workouts.first(where: { $0.id == trackedID }))
        XCTAssertEqual(retained.blueprint.id, trackedBlueprintID)
        XCTAssertEqual(retained.scheduledTimeMinutes, 450)
        XCTAssertTrue(retained.reminderEnabled)
        XCTAssertEqual(Calendar.current.component(.weekday, from: retained.date), Weekday.saturday.rawValue)
    }

    func testCoachContextUsesStableReferencesAndBoundedDerivedHistory() throws {
        let (store, _) = try makeStore()
        let start = Date()
        let profile = RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers)
        let workouts = (0..<30).map { index in
            ScheduledWorkout(blueprint: WorkoutBlueprint(
                date: Calendar.current.date(byAdding: .day, value: index, to: start)!,
                kind: .easy,
                title: "Run \(index)",
                steps: [],
                plannedDistanceMeters: 5_000,
                usesPaceTargets: true
            ), status: index == 0 ? .completed : .scheduled)
        }
        store.plan = TrainingPlan(goal: TrainingGoal(kind: .fiveK), profile: profile, workouts: workouts)
        store.profile = profile
        store.results = (0..<12).map { index in
            WorkoutResult(
                workoutID: UUID(),
                startedAt: Calendar.current.date(byAdding: .day, value: -index, to: start)!,
                duration: 1_800,
                distanceMeters: 5_000,
                averagePaceSecPerKm: 360,
                heartRateAverage: 150,
                location: .outdoor,
                route: [RoutePoint(latitude: 40, longitude: -73, timestamp: start)],
                source: .appleHealth
            )
        }

        // Asked after every workout has passed: nothing the coach can act on, so no references.
        // This used to yield all 30 -- completed runs numbered alongside future ones -- which is
        // how a runner late in a plan got a model that had seen forty finished runs and nothing
        // it could edit.
        let context = try XCTUnwrap(store.coachContext(asOf: Calendar.current.date(byAdding: .day, value: 30, to: start)!))
        XCTAssertTrue(context.workouts.isEmpty, "a past-only plan has nothing the coach can reference")

        // Asked at the start: index 0 is completed and drops out, the 29 upcoming runs are
        // numbered in date order from w1, and the model's window caps them at 28.
        let upcoming = try XCTUnwrap(store.coachContext(asOf: start))
        XCTAssertEqual(upcoming.workouts.count, CoachPlanRules.modelReferenceLimit)
        XCTAssertEqual(upcoming.workouts.first?.reference, "w1")
        XCTAssertEqual(upcoming.workouts.first?.title, "Run 1", "the completed run 0 must not take w1")
        XCTAssertEqual(upcoming.workouts.last?.reference, "w28")
        XCTAssertEqual(upcoming.workouts.last?.title, "Run 28")
        XCTAssertEqual(context.recentResults.count, 8)
        XCTAssertEqual(context.recentResults.first?.distanceMeters, 5_000)
        XCTAssertEqual(context.adherence, 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertNil(store.coachContext(asOf: Date(timeIntervalSinceReferenceDate: .nan)))
    }

    func testBlockedCoachProposalAndMissingPlanCannotMutateOrCreateHistory() throws {
        let (store, context) = try makeStore()
        let blocked = store.previewCoachIntent(.cutIntensity)
        XCTAssertFalse(blocked.isApplicable)
        guard case .rejected = store.applyCoachProposal(blocked) else {
            return XCTFail("A blocked proposal must not apply without an active plan")
        }
        XCTAssertNil(store.plan)
        XCTAssertEqual(planChangeCount(context), 0)

        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let invalid = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: UUID()))
        XCTAssertFalse(invalid.isApplicable)
        guard case .rejected = store.applyCoachProposal(invalid) else {
            return XCTFail("An unknown workout must not apply")
        }
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachRetargetProposalRejectsRegeneratedPlanTampering() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let original = try XCTUnwrap(store.plan)
        let originalProfile = try XCTUnwrap(store.profile)
        let proposal = store.previewCoachIntent(.retargetVDOT(target: originalProfile.vdot * 1.02))
        XCTAssertTrue(proposal.isApplicable)

        var tampered = proposal
        guard let index = tampered.proposedPlan.workouts.firstIndex(where: {
            $0.date >= Calendar.current.startOfDay(for: Date()) && $0.status == .scheduled
        }) else {
            return XCTFail("The regenerated proposal should contain future scheduled work")
        }
        tampered.proposedPlan.workouts[index].blueprint.title = "Unauthorized future workout"
        var forgedChanges = CoachPlanRules.changes(
            from: tampered.basePlan,
            to: tampered.proposedPlan,
            calendar: Calendar.current
        )
        forgedChanges.append(CoachProposalChange(
            reference: "PROFILE",
            kind: .updated,
            before: "VDOT \(String(format: "%.1f", originalProfile.vdot))",
            after: "VDOT \(String(format: "%.1f", tampered.proposedProfile.vdot))"
        ))
        tampered.changes = forgedChanges

        guard case .rejected = store.applyCoachProposal(tampered) else {
            return XCTFail("A regenerated plan with a forged future workout must be rejected")
        }
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(store.profile, originalProfile)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testCoachPersistenceFailureRestoresInMemoryState() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        store.save()
        let workout = try XCTUnwrap(store.plan?.workouts.first)
        let original = try XCTUnwrap(store.plan)
        let proposal = store.previewCoachIntent(.moveWorkoutIndoors(workoutID: workout.id))
        store.setForceSaveFailureAfterMutationForTesting(true)

        guard case .rejected = store.applyCoachProposal(proposal) else {
            return XCTFail("Expected persistence failure")
        }
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testTypedCoachResponseMapsStableWorkoutReferenceAndClarifiesMissingTravelDates() throws {
        let workoutID = UUID()
        let context = CoachContext(
            asOf: Date(),
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            currentWeekStart: Date(),
            workouts: [
                CoachContext.WorkoutReference(
                    id: workoutID,
                    reference: "w3",
                    date: Date(),
                    kind: .tempo,
                    title: "Tempo run",
                    status: .scheduled,
                    plannedDistanceMeters: 8_000,
                    location: .outdoor
                )
            ],
            recentResults: [],
            adherence: 1
        )

        let mapped = CoachIntentMapper.map(
            CoachTypedResponse(reply: "Moving w3 indoors.", intent: "moveWorkoutIndoors", workoutReference: "w3"),
            context: context
        )
        XCTAssertEqual(mapped, .moveWorkoutIndoors(workoutID: workoutID))

        let clarification = CoachIntentMapper.map(
            CoachTypedResponse(reply: "Which dates?", intent: "reshapeForTravel"),
            context: context
        )
        XCTAssertEqual(clarification, .clarificationRequired)
    }

    func testScheduleApplyFailureRestoresProfileAndPlan() throws {
        let (store, context) = try makeStore()
        store.plan = samplePlan()
        store.profile = store.plan?.profile
        let originalProfile = store.profile
        let originalWorkoutCount = store.plan?.workouts.count
        store.save()
        store.setForceSaveFailureAfterMutationForTesting(true)
        try? store.applyManagePlanSchedule(
            days: [.monday, .wednesday, .friday, .sunday],
            daysPerWeek: 4,
            longRunDay: .sunday
        )
        XCTAssertEqual(store.profile?.availableWeekdays, originalProfile?.availableWeekdays)
        XCTAssertEqual(store.plan?.workouts.count, originalWorkoutCount)
        XCTAssertEqual(planChangeCount(context), 0)

        let reloaded = AppStore()
        reloaded.attach(context: context)
        XCTAssertEqual(reloaded.profile?.availableWeekdays, originalProfile?.availableWeekdays)
    }

    func testApplyMissedWorkRequiresPreview() throws {
        let (store, context) = try makeStore()
        let missed = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            kind: .easy,
            title: "Missed",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [missed]
        )
        store.profile = store.plan?.profile
        store.save()
        let situation = try XCTUnwrap(store.missedWorkSituation)
        XCTAssertThrowsError(try store.applyMissedWork(choice: .skipMissed, situation: situation, preview: nil))
        XCTAssertEqual(planChangeCount(context), 0)
    }

    func testApplyMissedWorkWithPreviewWritesOneChange() throws {
        let (store, context) = try makeStore()
        let missed = ScheduledWorkout(blueprint: WorkoutBlueprint(
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            kind: .easy,
            title: "Missed",
            steps: [],
            plannedDistanceMeters: 5_000,
            usesPaceTargets: true
        ))
        store.plan = TrainingPlan(
            goal: TrainingGoal(kind: .fiveK),
            profile: RunnerProfile(ability: .intermediate, daysPerWeek: 4, longRunWeekday: .sunday, unit: .kilometers),
            workouts: [missed]
        )
        store.profile = store.plan?.profile
        store.save()
        let situation = try XCTUnwrap(store.missedWorkSituation)
        let preview = try XCTUnwrap(store.previewMissedWork(choice: .skipMissed, situation: situation))
        try store.applyMissedWork(choice: .skipMissed, situation: situation, preview: preview)
        XCTAssertEqual(planChangeCount(context), 1)
    }

    /// While NOT FEELING 100% is active the runner sees an overlay, not the plan the coach would
    /// edit. Editing intents must be refused -- for any mode, not just a pause -- and must say
    /// why, and an adjustment whose window has closed must not refuse anything.
    func testCoachRefusesEditsWhileNotFeeling100IsActive() throws {
        let (store, _) = try makeStore()
        store.plan = samplePlan(workoutDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        store.profile = store.plan?.profile

        for mode in [N100Mode.pause, .reducedDifficulty] {
            store.n100 = N100Adjustment(start: Date(), dayCount: 5, mode: mode, returnPace: .balanced)
            let blocked = store.previewCoachIntent(.cutIntensity)
            XCTAssertFalse(blocked.isApplicable)
            XCTAssertTrue(
                blocked.blockingWarnings.first?.message.contains("NOT FEELING 100%") ?? false,
                "\(mode): the refusal must say the adjustment is why, not fall through to a rule message"
            )
        }

        // Expired: started ten days ago for three days. The coach is free to edit again.
        store.n100 = N100Adjustment(
            start: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            dayCount: 3, mode: .pause, returnPace: .balanced
        )
        let afterwards = store.previewCoachIntent(.cutIntensity)
        XCTAssertFalse(
            afterwards.blockingWarnings.contains { $0.message.contains("NOT FEELING 100%") },
            "a closed window must not block"
        )
    }
}
