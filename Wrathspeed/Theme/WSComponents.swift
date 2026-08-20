import SwiftUI

struct WSEyebrow: View {
    var text: String
    var color: Color = WSColor.accent

    var body: some View {
        Text(text)
            .font(WSFont.ui(12, weight: .heavy))
            .tracking(3)
            .foregroundStyle(color)
    }
}

struct WSPrimaryButton: View {
    var title: String
    var height: CGFloat = 62
    var fontSize: CGFloat = 22
    var fill: Color = WSColor.accent
    var textColor: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WSFont.display(fontSize))
                .tracking(1)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(fill, in: RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct WSOutlineButton: View {
    var title: String
    var height: CGFloat = 52
    var color: Color = WSColor.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WSFont.ui(14, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                        .stroke(color, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct WSChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WSFont.ui(13, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(WSColor.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? WSColor.accentTint : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(selected ? WSColor.accent : WSColor.border, lineWidth: selected ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WSSelectRow<Accessory: View>: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(WSFont.ui(15, weight: .bold))
                    .foregroundStyle(WSColor.text)
                Spacer()
                accessory()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .fill(selected ? WSColor.accentTint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WSRadius.control, style: .continuous)
                    .stroke(selected ? WSColor.accent : WSColor.border, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct WSStepperControl: View {
    var valueText: String
    var decrement: () -> Void
    var increment: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            circleButton("−", outlined: true, label: "Decrease", action: decrement)
            Text(valueText)
                .font(WSFont.display(30))
                .foregroundStyle(WSColor.text)
                .frame(minWidth: 28)
                .multilineTextAlignment(.center)
            circleButton("+", outlined: false, label: "Increase", action: increment)
        }
    }

    private func circleButton(_ title: String, outlined: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WSFont.ui(18, weight: .heavy))
                .foregroundStyle(outlined ? WSColor.text : WSColor.accent)
                .frame(minWidth: 44, minHeight: 44)
                .overlay(
                    Circle().stroke(outlined ? Color.white.opacity(0.3) : WSColor.accent, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct WSHairlineRow: View {
    var label: String
    var value: String
    var valueColor: Color = WSColor.text
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(WSFont.ui(13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.60))
                Spacer()
                Text(value)
                    .font(WSFont.mono(13, weight: .bold))
                    .foregroundStyle(valueColor)
            }
            .padding(.vertical, 12)
            if showDivider {
                Rectangle().fill(WSColor.hairline).frame(height: 1)
            }
        }
    }
}

struct WSProgressBar: View {
    var progress: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WSColor.surface1)
                Capsule()
                    .fill(WSColor.accent)
                    .frame(width: max(0, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }
}

struct WSToast: View {
    var text: String

    var body: some View {
        Text(text)
            .font(WSFont.ui(12, weight: .heavy))
            .tracking(0.5)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
    }
}

struct WSAlert: View {
    var message: String
    var onOK: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Text("SOMETHING WENT WRONG")
                    .font(WSFont.display(26))
                    .tracking(0.5)
                    .foregroundStyle(WSColor.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                Text(message)
                    .font(WSFont.ui(13, weight: .medium))
                    .foregroundStyle(WSColor.text70)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                Button(action: onOK) {
                    Text("OK")
                        .font(WSFont.ui(14, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(WSColor.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .overlay(alignment: .top) {
                    Rectangle().fill(WSColor.hairlineStrong).frame(height: 1)
                }
            }
            .background(WSColor.bgAlert, in: RoundedRectangle(cornerRadius: WSRadius.alert, style: .continuous))
            .padding(.horizontal, 40)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, plan, history, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "TODAY"
        case .plan: "PLAN"
        case .history: "HISTORY"
        case .settings: "SETTINGS"
        }
    }
}

struct WSTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.label)
                        .font(WSFont.ui(11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(selection == tab ? WSColor.accent : WSColor.text35)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 22)
        .background(WSColor.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(WSColor.hairline).frame(height: 1)
        }
    }
}

struct WSScreen<Content: View>: View {
    var topPadding: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.top, topPadding)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(WSColor.bg.ignoresSafeArea())
    }
}
