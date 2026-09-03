import AVFoundation
import Foundation

@MainActor
final class RunAudioCoach: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func announceCompletedKilometre(
        _ kilometre: Int,
        averagePaceSecondsPerKm: Double
    ) {
        guard averagePaceSecondsPerKm.isFinite, averagePaceSecondsPerKm > 0 else { return }

        let totalSeconds = Int(averagePaceSecondsPerKm.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let text = "Kilometer \(kilometre). Durchschnittspace \(minutes) Minuten \(seconds) Sekunden pro Kilometer."

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
