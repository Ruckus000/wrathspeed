import SwiftUI
import WrathspeedCore

struct LiveRunView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let blueprint: WorkoutBlueprint

    var body: some View {
        let session = store.session
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(blueprint.title.uppercased())
                    .font(WSFont.ui(12, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(WSColor.text50)
                Spacer()
                Text(stepCount)
                    .font(WSFont.mono(11))
                    .foregroundStyle(WSColor.accent)
            }
            .padding(.horizontal, WSSpace.gutter)
            .padding(.top, 8)
            Text((session.stepper?.currentStep?.name ?? blueprint.title).uppercased())
                .font(WSFont.display(42))
                .tracking(0.5)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 6)
            chip
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 14)
            VStack(spacing: 6) {
                Text(paceHero)
                    .font(WSFont.display(140))
                    .foregroundStyle(WSColor.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("CURRENT PACE /\(WSFormat.unitSuffix(store.unit))")
                    .font(WSFont.ui(13, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(WSColor.text50)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            zoneBand
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 24)
            metricsRow
                .padding(.horizontal, WSSpace.gutter)
                .padding(.top, 24)
            Spacer()
            transport
            Text(statusText)
                .font(WSFont.ui(11, weight: .medium))
                .foregroundStyle(WSColor.text35)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 40)
        }
        .background(WSColor.bg.ignoresSafeArea())
        .onChange(of: store.celebration?.id) { _, value in
            if value != nil { dismiss() }
        }
    }

    private var stepCount: String {
        let session = store.session
        let total = max(blueprint.steps.count, 1)
        let current = min((session.stepper?.stepIndex ?? 0) + 1, total)
        return "STEP \(current)/\(total)"
    }

    private var paceHero: String {
        guard let pace = store.session.metrics.currentPaceSecPerKm else { return "–:––" }
        return WSFormat.paceClock(pace, unit: store.unit)
    }

    private var chip: some View {
        let model = CoachingCopy.chip(
            currentPaceSecPerKm: store.session.metrics.currentPaceSecPerKm,
            targetSecPerKm: targetPace,
            paused: store.session.isPaused,
            style: store.cueStyle
        )
        return Text(model.text)
            .font(WSFont.ui(12, weight: .heavy))
            .tracking(1)
            .foregroundStyle(model.kind == .off ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    model.kind == .inZone ? WSColor.accent
                        : model.kind == .off ? Color.white
                        : WSColor.surface1
                )
            )
    }

    private var targetPace: TimeInterval? {
        guard let step = store.session.stepper?.currentStep,
              case .zone(let zone) = step.intensity
        else { return nil }
        return store.zones?.secondsPerKilometer(for: zone)
    }

    private var zoneBand: some View {
        let target = targetPace ?? 360
        let current = store.session.metrics.currentPaceSecPerKm ?? target
        let low = target * 0.85
        let high = target * 1.20
        let span = max(high - low, 1)
        let fast = target * 0.95
        let slow = target * 1.05
        return WSZoneBand(
            lowLabel: WSFormat.paceClock(low, unit: store.unit),
            midLabel: "TARGET \(WSFormat.paceClock(fast, unit: store.unit))–\(WSFormat.paceClock(slow, unit: store.unit))",
            highLabel: WSFormat.paceClock(high, unit: store.unit),
            bandStart: CGFloat((fast - low) / span),
            bandWidth: CGFloat((slow - fast) / span),
            needle: CGFloat(min(1, max(0, (current - low) / span)))
        )
    }

    private var metricsRow: some View {
        let metrics = LiveMetric.allCases.filter { store.liveMetrics.contains($0) }
        return HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
                VStack(spacing: 4) {
                    Text(metric.liveLabel(unit: store.unit))
                        .font(WSFont.mono(10))
                        .tracking(1)
                        .foregroundStyle(WSColor.text40)
                    Text(metricValue(metric))
                        .font(WSFont.display(30))
                        .foregroundStyle(WSColor.text)
                }
                .frame(maxWidth: .infinity)
                if index < metrics.count - 1 {
                    Rectangle().fill(WSColor.hairline).frame(width: 1, height: 44)
                }
            }
        }
    }

    private func metricValue(_ metric: LiveMetric) -> String {
        let metrics = store.session.metrics
        switch metric {
        case .time: return WSFormat.duration(metrics.elapsed)
        case .distance: return WSFormat.distanceValue(metrics.distanceMeters, unit: store.unit)
        case .heartRate: return metrics.heartRate.map { "\(Int($0.rounded()))" } ?? "—"
        }
    }

    private var transport: some View {
        HStack(spacing: 30) {
            circle("LAP", size: 62) { store.session.skipStep() }
            Button {
                store.session.isPaused ? store.session.resume() : store.session.pause()
            } label: {
                ZStack {
                    Circle().fill(WSColor.accent)
                    if store.session.isPaused {
                        Triangle()
                            .fill(.white)
                            .frame(width: 22, height: 26)
                            .offset(x: 3)
                    } else {
                        HStack(spacing: 7) {
                            Capsule().fill(.white).frame(width: 8, height: 30)
                            Capsule().fill(.white).frame(width: 8, height: 30)
                        }
                    }
                }
                .frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            circle("END", size: 62) {
                Task { await store.session.end() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func circle(_ title: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WSFont.ui(12, weight: .heavy))
                .tracking(1)
                .foregroundStyle(WSColor.text)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch store.session.launchState {
        case .idle: "Starting…"
        case .waitingForWatch: "Waiting for Apple Watch to start…"
        case .recording: WCSessionBridge.isWatchAppInstalled ? "Watch is recording. Phone can disconnect." : "Phone is recording."
        case let .failed(message): "Couldn’t start: \(message)"
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
