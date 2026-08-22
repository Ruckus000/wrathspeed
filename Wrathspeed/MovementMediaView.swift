import AVKit
import SwiftUI
import WrathspeedCore

/// Loops a bundled demo clip for a movement, falling back to its SF Symbol when no clip
/// is bundled. Silent and gapless: these play behind a workout where audio cues matter,
/// so the clip must never take the audio session or interrupt music.
struct MovementMediaView: View {
    let movementID: String
    let symbolName: String
    var height: CGFloat = 220

    @Environment(\.mediaLibrary) private var library

    var body: some View {
        Group {
            if let url = library.url(for: movementID) {
                LoopingVideoView(url: url)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .background(WSColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Demonstration loop")
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WSColor.text40)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .background(WSColor.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// AVPlayerLayer wrapper that loops one local file forever.
///
/// `AVPlayerLooper` over an `AVQueuePlayer` rather than restarting on
/// `didPlayToEndTime`, because the notification round-trip drops a frame at every loop
/// boundary and these clips are only a couple of seconds long.
private struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ view: LoopingPlayerUIView, context: Context) {
        view.update(url: url)
    }

    static func dismantleUIView(_ view: LoopingPlayerUIView, coordinator: ()) {
        view.stop()
    }
}

private final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?
    private var currentURL: URL?

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(url: URL) {
        super.init(frame: .zero)
        playerLayer.videoGravity = .resizeAspect
        update(url: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        stop()

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        // Muted so a demo loop never ducks the user's music or the spoken cues.
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        playerLayer.player = queue
        player = queue
        queue.play()
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        playerLayer.player = nil
    }
}

// MARK: - Environment

private struct MediaLibraryKey: EnvironmentKey {
    // Loaded once per process. Falls back to an empty library, which renders symbols.
    static let defaultValue = MediaLibrary.makeDefault()
}

extension EnvironmentValues {
    var mediaLibrary: MediaLibrary {
        get { self[MediaLibraryKey.self] }
        set { self[MediaLibraryKey.self] = newValue }
    }
}
