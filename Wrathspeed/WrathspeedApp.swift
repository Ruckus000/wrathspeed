import SwiftData
import SwiftUI

@main
struct WrathspeedApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [
            SnapshotEntity.self,
            MigrationMarkerEntity.self,
            AppSettingsEntity.self,
            TrainingPlanEntity.self,
            ScheduledWorkoutEntity.self,
            WorkoutResultEntity.self,
            StrengthSessionEntity.self,
            StrengthSessionResultEntity.self,
            MobilitySessionEntity.self,
            MobilitySessionResultEntity.self,
            PlanAdjustmentEntity.self,
            PlanChangeEntity.self,
            ActiveSessionSnapshotEntity.self,
            PendingHealthOpEntity.self,
        ])
    }
}
