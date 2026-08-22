import CoreGraphics
import Foundation

/// The Rake — the Wrathspeed mark, transcribed from the locked `Wrathspeed Mark.dc.html`
/// brand spec.
///
/// Foundation and CoreGraphics only, deliberately: this file compiles both into the app
/// targets and against the macOS toolchain for `Tools/brand/render-icons.swift`, so the
/// SwiftUI mark and the exported app icons are cut from one set of coordinates.
///
/// Units are the spec's artboard units, and y grows downward as it does in SVG and in
/// SwiftUI's `Path`. Callers work in points via ``path(_:fitting:)``.
enum WSMarkVariant {
    /// Three cuts through the stroke. The spec's primary, for 24pt and up.
    case raked
    /// One unbroken outline. Below 24pt, embroidery, etch.
    case solid
    /// The mark and its cuts knocked out of a leaning plate. For photography and noise.
    case plate
}

enum WSMarkGeometry {
    /// Square artboard, 170u. The mark is 137u x 134u inside a 16u margin.
    static let artboard = CGRect(x: -16, y: -56, width: 170, height: 170)

    /// The mark below 24pt: one outline, 26u horizontal weight, 7 degrees of italic.
    static var solid: CGPath { skeleton }

    /// The primary mark: the skeleton with the three rake cuts taken out of it.
    static var raked: CGPath { skeleton.subtracting(cuts) }

    /// The plate: a leaning parallelogram with the mark *and* its cut bands knocked
    /// through it, so the stripes run the full width of the plate.
    static var plate: CGPath {
        var inset = plateInset
        let combined = skeleton.union(cuts)
        let knockout = combined.copy(using: &inset) ?? combined
        return plateField.subtracting(knockout)
    }

    /// The named variant, aspect-fitted into `rect`.
    static func path(_ variant: WSMarkVariant, fitting rect: CGRect) -> CGPath {
        let source: CGPath = switch variant {
        case .raked: raked
        case .solid: solid
        case .plate: plate
        }
        let scale = min(rect.width / artboard.width, rect.height / artboard.height)
        var fit = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -artboard.midX, y: -artboard.midY)
        return source.copy(using: &fit) ?? source
    }

    // MARK: - Construction

    /// 7 degrees of italic, applied as a horizontal skew exactly as the spec's SVG does.
    private static let italic = CGAffineTransform(
        a: 1, b: 0,
        c: CGFloat(tan(-7 * Double.pi / 180)), d: 1,
        tx: 0, ty: 0
    )

    /// translate(14,-8) scale(0.78) — the plate's knockout sits smaller and higher than
    /// the mark itself.
    private static let plateInset = CGAffineTransform(translationX: 14, y: -8)
        .scaledBy(x: 0.78, y: 0.78)

    /// One outline: base at 0u, cap at 96u, tip at -38u. Mitred apexes throughout.
    private static var skeleton: CGPath {
        polygon([
            (0, 0), (26, 0), (42, 36.6), (58, 0), (74, 36.6), (90, 0),
            (132.6, -38), (74, 96), (58, 59.4), (42, 96),
        ], transform: italic)
    }

    /// Three cuts perpendicular to the stroke, 38u apart, tapered 4u to 3u. Drawn in
    /// unskewed artboard space — the italic is already in the stroke they cross.
    private static var cuts: CGPath {
        let bands: [[(CGFloat, CGFloat)]] = [
            [(-20, 40), (150, -34), (150, -31), (-20, 47)],
            [(-20, 78), (150, 3.6), (150, 7.1), (-20, 87)],
            [(-20, 116), (150, 41.6), (150, 45.6), (-20, 127)],
        ]
        let path = CGMutablePath()
        for band in bands { path.addPath(polygon(band)) }
        return path
    }

    private static var plateField: CGPath {
        polygon([(18, -46), (152, -46), (126, 108), (-8, 108)])
    }

    private static func polygon(
        _ points: [(CGFloat, CGFloat)],
        transform: CGAffineTransform = .identity
    ) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) }, transform: transform)
        path.closeSubpath()
        return path
    }
}
