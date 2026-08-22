import SwiftUI
import WrathspeedCore

struct CelebrationView: View {
    @Environment(AppStore.self) private var store
    let payload: CelebrationPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(WSFormat.weekdayDate(payload.date)) · \(payload.title.uppercased())")
                .wsType(.label, weight: .heavy, tracking: 3)
                .foregroundStyle(Color.black.opacity(0.55))
            Text("DONE.")
                .wsType(.hero)
                .foregroundStyle(.white)
                .padding(.top, 8)
            HStack {
                stat("DISTANCE", WSFormat.distanceValue(payload.distanceMeters, unit: store.unit))
                stat("TIME", WSFormat.duration(payload.duration))
                stat("AVG PACE", payload.averagePaceSecPerKm.map { WSFormat.paceClock($0, unit: store.unit) } ?? "—")
            }
            .padding(.top, 16)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.black.opacity(0.25)).frame(height: 2)
            }
            .padding(.top, 26)
            if let pr = payload.prCopy {
                VStack(alignment: .leading, spacing: 4) {
                    Text("★ NEW PR")
                        .wsType(.label, weight: .heavy, tracking: 2)
                    Text(pr)
                        .wsType(.body, weight: .heavy)
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WSColor.celOverlay, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 18)
            }
            HStack(spacing: 10) {
                card("STREAK", "\(payload.streak) DAYS")
                card("WEEK", "\(WSFormat.distanceValue(payload.weekCompletedMeters, unit: store.unit, fraction: 0))/\(WSFormat.distanceValue(payload.weekPlannedMeters, unit: store.unit, fraction: 0)) \(WSFormat.unitSuffix(store.unit))")
            }
            .padding(.top, 10)
            if let suggestion = payload.suggestion {
                VStack(alignment: .leading, spacing: 0) {
                    WSEyebrow(text: "PACE SUGGESTION")
                    Text(suggestion.reason)
                        .wsType(.label, weight: .medium)
                        .foregroundStyle(WSColor.text70)
                        .padding(.top, 6)
                    Text("VDOT \(WSFormat.vdot(payload.previousVDOT ?? store.profile?.vdot ?? 0)) → \(WSFormat.vdot(suggestion.newVDOT))")
                        .wsType(.displayXS)
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    HStack(spacing: 10) {
                        Button("ACCEPT") { store.acceptVDOTSuggestion() }
                            .wsType(.body, weight: .heavy, tracking: 1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(WSColor.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Button("NOT NOW") { store.declineVDOTSuggestion() }
                            .wsType(.body, weight: .heavy, tracking: 1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                    }
                    .padding(.top, 12)
                }
                .padding(16)
                .background(WSColor.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 10)
            }
            Spacer()
            WSPrimaryButton(title: "BACK TO TODAY", height: 60, role: .displayXS, fill: .white, textColor: .black) {
                store.celebration = nil
                store.selectedTab = .today
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 54)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WSColor.accent.ignoresSafeArea())
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .wsType(.metricS, weight: .bold)
                .foregroundStyle(Color.black.opacity(0.55))
            Text(value)
                .wsType(.displayS)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .wsType(.metricS, weight: .bold)
                .foregroundStyle(Color.white.opacity(0.8))
            Text(value)
                .wsType(.displayS)
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WSColor.celOverlay, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
