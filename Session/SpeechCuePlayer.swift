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

    func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
    }

    func speak(_ cue: Cue) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: phrase(for: cue))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.preUtteranceDelay = 0
        synthesizer.speak(utterance)
        playHaptic(for: cue)
    }

    private func phrase(for cue: Cue) -> String {
        switch cue {
        case .stepStarted(let name): "\(name)."
        case .stepCompleted(let name): "\(name) complete."
        case .speedUp: "Speed up."
        case .slowDown: "Slow down."
        case .split(let km, _): "Kilometer \(km)."
        }
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
        switch cue {
        case .speedUp, .slowDown:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }
}
