// Render the app icons from the Rake geometry.
//
// The icons are not hand-exported artwork. They are drawn from the same
// Design/WSMarkGeometry.swift the SwiftUI mark uses, so the icon on the home screen and
// the mark inside the app cannot drift apart. Re-run this whenever the geometry changes.
//
// No third-party dependencies -- CoreGraphics and ImageIO ship with the toolchain that
// already has to be installed to build the app at all.
//
// Usage:
//     Tools/brand/render-icons.sh          # write both icons
//     Tools/brand/render-icons.sh --check  # render and compare, write nothing

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Icon {
    let path: String
    /// Fraction of the canvas left empty on every side, on top of the artboard's own 16u
    /// margin. watchOS masks the icon to a circle, which eats into that margin.
    let inset: CGFloat
}

private let icons = [
    Icon(path: "Wrathspeed/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png", inset: 0),
    Icon(path: "WrathspeedWatch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png", inset: 0.12),
]

private let side = 1024
private let field = CGColor(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0B / 255, alpha: 1)
private let ink = CGColor(red: 0xFF / 255, green: 0x31 / 255, blue: 0x28 / 255, alpha: 1)

private func render(_ icon: Icon) -> CGImage {
    // No alpha channel: the App Store rejects icons that carry one.
    guard let context = CGContext(
        data: nil,
        width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("could not open a \(side)x\(side) bitmap context") }

    let canvas = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
    context.setFillColor(field)
    context.fill(canvas)

    // CoreGraphics is y-up; the geometry, like the SVG it came from, is y-down.
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)

    context.setFillColor(ink)
    context.addPath(WSMarkGeometry.path(.raked, fitting: canvas.insetBy(
        dx: canvas.width * icon.inset,
        dy: canvas.height * icon.inset
    )))
    context.fillPath()

    guard let image = context.makeImage() else { fatalError("could not rasterise \(icon.path)") }
    return image
}

private func encode(_ image: CGImage) -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("could not open a PNG encoder") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not encode PNG") }
    return data as Data
}

@main
enum RenderIcons {
    static func main() throws {
        let checkOnly = CommandLine.arguments.contains("--check")
        var stale: [String] = []

        for icon in icons {
            let url = URL(fileURLWithPath: icon.path)
            let rendered = encode(render(icon))
            if (try? Data(contentsOf: url)) == rendered {
                print("unchanged  \(icon.path)")
                continue
            }
            if checkOnly {
                stale.append(icon.path)
                continue
            }
            try rendered.write(to: url)
            print("wrote      \(icon.path)  \(side)x\(side)  \(rendered.count) bytes")
        }

        guard stale.isEmpty else {
            var message = "error: these icons no longer match the geometry"
                + " -- run Tools/brand/render-icons.sh\n"
            for path in stale { message += "  \(path)\n" }
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }
}
