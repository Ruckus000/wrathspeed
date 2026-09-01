import SwiftUI

enum WSColor {
    static let bg = Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255)
    static let bgSheet = Color(red: 19 / 255, green: 19 / 255, blue: 21 / 255)
    static let bgAlert = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)
    /// A card sitting *on* a sheet, where `bgSheet` is the ground rather than the card. Reads
    /// as inset because it is darker than what is behind it -- the preflight step cards.
    static let bgInset = Color(red: 15 / 255, green: 15 / 255, blue: 17 / 255)
    static let accent = Color(red: 1, green: 49 / 255, blue: 40 / 255)
    static let surface1 = Color(red: 35 / 255, green: 35 / 255, blue: 37 / 255)
    static let surface2 = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    static let surface3 = Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255)
    static let liveActivity = Color(red: 17 / 255, green: 17 / 255, blue: 19 / 255)
    /// Ground of an inset segmented track. Measured off the design as rgb(11, 11, 12) --
    /// deliberately not `bg` at rgb(10, 10, 11), which is a near-miss rather than the same
    /// colour, and reads flat when a track sits directly on the screen background.
    static let trackGround = Color(red: 11 / 255, green: 11 / 255, blue: 12 / 255)
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
    /// The edge of a grouped list card. Softer than `hairline`: measured at 0.07 in the
    /// design, where it has to read as a container edge without competing with the rows.
    static let hairlineSoft = Color.white.opacity(0.07)
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
    /// Grouped list card: Settings, the movement library.
    static let list: CGFloat = 10
    /// Ground of an inset segmented control. Distinct from `track`, which is the 4pt radius
    /// of a progress bar.
    static let segmentTrack: CGFloat = 7
    static let pill: CGFloat = 999
    static let track: CGFloat = 4
}

enum WSSpace {
    static let gutter: CGFloat = 24
    /// Side margin of a grouped list card. Narrower than `gutter` on purpose -- the design
    /// insets the card less than the text around it, so the card reads as a wider surface.
    static let cardGutter: CGFloat = 20
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
