import AVFoundation
import WrathspeedCore

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

final class SpeechCuePlayer: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    var isEnabled = true
    var cueStyle: CueStyle = .standard

    func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    func speak(_ cue: Cue) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: cueStyle.phrase(for: cue))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.preUtteranceDelay = 0
        synthesizer.speak(utterance)
        playHaptic(for: cue)
    }

    private func playHaptic(for cue: Cue) {
        #if os(watchOS)
        let type: WKHapticType = {
            switch cue {
            case .speedUp, .slowDown: .directionUp
            case .stepStarted, .stepCompleted: .notification
            case .split: .click
            }
        }()
        WKInterfaceDevice.current().play(type)
        #elseif os(iOS)
        Task { @MainActor in
            switch cue {
            case .speedUp, .slowDown:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        #endif
    }
}
