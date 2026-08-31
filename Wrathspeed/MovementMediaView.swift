import AVKit
import SwiftUI
import WrathspeedCore

/// Plays a bundled demo clip for a movement, falling back to its SF Symbol when no clip
/// is bundled. Silent and gapless: these play behind a workout where audio cues matter,
/// so the clip must never take the audio session or interrupt music.
///
/// Playback is under the user's control. The clip starts playing on the surfaces where the
/// demo is the point of the screen, but a tap anywhere on it -- or on the corner button --
/// pauses and resumes. Two reasons this is a control and not just an autoplaying loop:
/// a looping figure beside a cue you are trying to read is a distraction you cannot switch
/// off, and Reduce Motion is a request to stop exactly this kind of thing.
struct MovementMediaView: View {
    let movementID: String
    let symbolName: String
    var height: CGFloat = 220
    /// Whether the loop runs on appear. Reduce Motion overrides this to `false`; the user
    /// can still start it by hand, which is the difference between honouring the setting
    /// and removing the feature.
    var autoplay: Bool = true

    @Environment(\.mediaLibrary) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPlaying = false
    /// What the user last asked for, or nil while they have not asked. Kept apart from
    /// `isPlaying` because `onDisappear` pauses for resource reasons, not because the user
    /// wanted it stopped -- folding the two together leaves a clip that scrolled off screen
    /// once permanently paused when it comes back.
    @State private var userWantsPlaying: Bool?

    private var wantsAutoplay: Bool { autoplay && !reduceMotion }

    var body: some View {
        Group {
            if let url = library.url(for: movementID) {
                clip(url: url)
            } else {
                placeholder
            }
        }
    }

    private func clip(url: URL) -> some View {
        LoopingVideoView(url: url, isPlaying: isPlaying)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(WSColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // Paused is a state the user has to be able to see and undo, so it gets a target
            // sized like one rather than a subtitle.
            .overlay {
                if !isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .padding(22)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) { toggleButton }
            // The whole clip is the second, larger hit target for the same action. The corner
            // button alone is a 44pt goal on a 280pt surface.
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture { toggle() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Demonstration loop")
            .onAppear { isPlaying = userWantsPlaying ?? wantsAutoplay }
            // Never leave a decoder running behind a screen that is gone.
            .onDisappear { isPlaying = false }
    }

    private var toggleButton: some View {
        Button(action: toggle) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(10)
        // 32pt of glyph plus 10pt of padding reaches the 44pt minimum target.
        .contentShape(Rectangle())
        .accessibilityLabel(isPlaying ? "Pause demonstration" : "Play demonstration")
        .accessibilityIdentifier("movement_media_playpause")
    }

    private var placeholder: some View {
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

    private func toggle() {
        let next = !isPlaying
        userWantsPlaying = next
        withAnimation(.easeInOut(duration: 0.15)) { isPlaying = next }
    }
}

/// AVPlayerLayer wrapper that loops one local file, playing only while asked to.
private struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url, isPlaying: isPlaying)
    }

    func updateUIView(_ view: LoopingPlayerUIView, context: Context) {
        view.update(url: url)
        view.setPlaying(isPlaying)
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
    private var isPlaying: Bool

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(url: URL, isPlaying: Bool) {
        self.isPlaying = isPlaying
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
        // `AVPlayerLooper` over an `AVQueuePlayer` rather than restarting on
        // `didPlayToEndTime`, because the notification round-trip drops a frame at every
        // loop boundary and these clips are only a couple of seconds long.
        looper = AVPlayerLooper(player: queue, templateItem: item)
        playerLayer.player = queue
        player = queue
        // A paused player shows its first frame, which is the poster the play button sits on.
        if isPlaying { queue.play() }
    }

    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        if playing {
            player?.play()
        } else {
            player?.pause()
        }
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
