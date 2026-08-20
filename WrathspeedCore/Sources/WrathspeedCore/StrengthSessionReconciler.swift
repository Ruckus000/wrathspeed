import Foundation

public enum StrengthSessionReconciler {
    public static func reconcile(
        existing: [StrengthSession],
        generated: [StrengthSession],
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> [StrengthSession] {
        let today = calendar.startOfDay(for: date)
        let past = existing.filter { $0.date < today }
        let future = generated.filter { $0.date >= today }
        return (past + future).sorted { $0.date < $1.date }
    }
}
