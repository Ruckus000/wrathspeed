import SwiftUI

/// How the mark is inked. The spec allows exactly these; red is a field colour only in
/// `.reversed`, never a second colour inside the cuts.
enum WSMarkStyle {
    /// Accent red. The default, on any dark field.
    case primary
    /// Near-black, for sitting on an accent-red field.
    case reversed
    /// Near-black, for print, documents and partner lockups on white.
    case monoDark
    /// White, for the size ladder and the caged lockup.
    case monoLight

    var ink: Color {
        switch self {
        case .primary: WSColor.accent
        case .reversed, .monoDark: WSColor.bg
        case .monoLight: .white
        }
    }
}

/// The Rake as a `Shape`, so it can fill, mask or clip like any other.
struct WSMarkShape: Shape {
    var variant: WSMarkVariant = .raked

    func path(in rect: CGRect) -> Path {
        Path(WSMarkGeometry.path(variant, fitting: rect))
    }
}

/// The Wrathspeed mark.
///
/// Picks its own variant from the rendered size: raked at 24pt and above, solid below.
/// The spec is unambiguous that this is not a per-site judgement call -- under 24pt the
/// cuts fill in and the mark reads as dirt -- so the rule lives here rather than at every
/// call site. Pass `variant:` only to ask for `.plate`, or to force solid in print.
struct WSMark: View {
    /// Below this, the cuts close up. Favicons and watch complications included.
    static let rakeFloor: CGFloat = 24

    var size: CGFloat
    var style: WSMarkStyle = .primary
    var variant: WSMarkVariant?
    /// `nil` marks the mark as decorative -- use it wherever "Wrathspeed" is already
    /// spelled out beside it.
    var label: String? = "Wrathspeed"

    /// The variant this mark will actually draw, after the size rule.
    var resolvedVariant: WSMarkVariant {
        variant ?? (size >= Self.rakeFloor ? .raked : .solid)
    }

    var body: some View {
        WSMarkShape(variant: resolvedVariant)
            .fill(style.ink)
            .frame(width: size, height: size)
            .accessibilityHidden(label == nil)
            .accessibilityLabel(label ?? "")
            .accessibilityAddTraits(.isImage)
    }
}

#Preview {
    VStack(spacing: 28) {
        HStack(spacing: 24) {
            WSMark(size: 128)
            WSMark(size: 64)
            WSMark(size: 40)
            WSMark(size: 24)
            WSMark(size: 16)
            WSMark(size: 12)
        }
        WSMark(size: 96, style: .monoLight, variant: .plate)
    }
    .padding(40)
    .background(WSColor.bg)
}
