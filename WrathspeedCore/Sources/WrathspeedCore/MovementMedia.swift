import Foundation

/// How a clip was drawn. Surfaced so the UI can treat the two differently if it ever
/// needs to, and so a future re-source can find the odd ones out.
public enum ClipStyle: String, Codable, Sendable {
    /// 3D anatomical render, working muscles highlighted, white background. The house style.
    case anatomicalRender = "anatomical-render"
    /// Photographic demo of a real person, built into a loop from a start and end frame.
    case photo
    /// Flat vector illustration, a single held frame. Only where the other two have nothing.
    case illustration
}

public struct MovementClip: Codable, Equatable, Sendable {
    public var file: String
    public var style: ClipStyle
    public var sourceRepo: String
    public var sourceRef: String
    /// Set when the artwork shows a close variant rather than the exact movement.
    public var approximate: String?
    public var bytes: Int?
}

public struct MediaManifest: Codable, Equatable, Sendable {
    public var clips: [String: MovementClip]
}

/// Resolves a movement id to its bundled demo clip.
///
/// Deliberately total: a missing manifest, a missing entry, or a missing file all just
/// mean "no clip", and the caller falls back to the movement's SF Symbol. Media is a
/// nice-to-have layered onto content that already stands on its own, so nothing here
/// should ever be able to take a workout screen down.
public struct MediaLibrary: Sendable {
    public let clips: [String: MovementClip]
    private let urls: [String: URL]

    /// Loads the manifest and resolves every clip that is actually present on disk.
    /// `Bundle` is not `Sendable`, so URLs are resolved once here rather than held.
    public init(bundle: Bundle? = nil) throws {
        let bundle = bundle ?? Bundle.module
        guard let url = bundle.url(forResource: "media_manifest", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest = try JSONDecoder().decode(MediaManifest.self, from: Data(contentsOf: url))
        self.clips = manifest.clips

        var resolved: [String: URL] = [:]
        for (id, clip) in manifest.clips {
            let name = (clip.file as NSString).deletingPathExtension
            let ext = (clip.file as NSString).pathExtension
            if let fileURL = bundle.url(forResource: name, withExtension: ext, subdirectory: "Media") {
                resolved[id] = fileURL
            }
        }
        self.urls = resolved
    }

    private init(clips: [String: MovementClip], urls: [String: URL]) {
        self.clips = clips
        self.urls = urls
    }

    /// An empty library. Every lookup misses, so every caller falls back to symbols.
    public static let empty = MediaLibrary(clips: [:], urls: [:])

    /// Never throws — an unreadable manifest degrades to symbol-only rather than failing launch.
    public static func makeDefault(bundle: Bundle? = nil) -> MediaLibrary {
        (try? MediaLibrary(bundle: bundle)) ?? .empty
    }

    public func clip(for movementID: String) -> MovementClip? {
        clips[movementID]
    }

    /// The playable file, or nil when this movement has no clip bundled.
    public func url(for movementID: String) -> URL? {
        urls[movementID]
    }

    public func hasClip(for movementID: String) -> Bool {
        urls[movementID] != nil
    }

    /// Ids that resolved to a real file on disk.
    public var availableIDs: Set<String> {
        Set(urls.keys)
    }
}
