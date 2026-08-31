import SwiftUI

enum WSColor {
    static let bg = Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255)
    static let bgSheet = Color(red: 19 / 255, green: 19 / 255, blue: 21 / 255)
    static let bgAlert = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)
    static let accent = Color(red: 1, green: 49 / 255, blue: 40 / 255)
    static let surface1 = Color(red: 35 / 255, green: 35 / 255, blue: 37 / 255)
    static let surface2 = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    static let surface3 = Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255)
    static let liveActivity = Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)
    static let destructive = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let accentBand = accent.opacity(0.40)
    static let accentTint = accent.opacity(0.12)
    static let celOverlay = Color.black.opacity(0.28)
    static let text = Color.white
    /// Card body copy. Brighter than `text70` because the instruction card sets it against
    /// `bgSheet` rather than `bg`, and 0.70 loses too much contrast on the lighter ground.
    static let text85 = Color.white.opacity(0.85)
    static let text70 = Color.white.opacity(0.70)
    static let text50 = Color.white.opacity(0.50)
    static let text45 = Color.white.opacity(0.45)
    static let text40 = Color.white.opacity(0.40)
    static let text35 = Color.white.opacity(0.35)
    static let hairline = Color.white.opacity(0.10)
    static let hairlineStrong = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.16)
}

enum WSRadius {
    static let control: CGFloat = 6
    static let sheet: CGFloat = 20
    static let alert: CGFloat = 14
    /// Inset cards -- instruction block, cue block, the strength player's mode card.
    static let card: CGFloat = 12
    static let pill: CGFloat = 999
    static let track: CGFloat = 4
}

enum WSSpace {
    static let gutter: CGFloat = 24
    static let sheetBottom: CGFloat = 52
}

enum WSMotion {
    static let sheet: Double = 0.25
    static let pop: Double = 0.30
    static let alert: Double = 0.18
    static let toast: Double = 2.4
}

struct WSZoneBand: View {
    var lowLabel: String
    var midLabel: String
    var highLabel: String
    var bandStart: CGFloat
    var bandWidth: CGFloat
    var needle: CGFloat
    var height: CGFloat = 10

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(WSColor.surface1)
                    Capsule()
                        .fill(WSColor.accentBand)
                        .frame(width: max(4, bandWidth * width))
                        .offset(x: max(0, min(width - 4, bandStart * width)))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: height + 4)
                        .offset(x: max(0, min(width - 3, needle * width)))
                }
            }
            .frame(height: height)
            if !lowLabel.isEmpty || !midLabel.isEmpty || !highLabel.isEmpty {
                HStack {
                    Text(lowLabel)
                    Spacer()
                    Text(midLabel).foregroundStyle(WSColor.accent)
                    Spacer()
                    Text(highLabel)
                }
                .wsType(.metricS)
                .foregroundStyle(WSColor.text40)
            }
        }
    }
}
