import Foundation
import AVFoundation

final class RestTimerAudioAlert {
    static let shared = RestTimerAudioAlert()
    private var player: AVAudioPlayer?

    private init() {}

    func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let url = try toneURL()
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()
        } catch {
            // Notification/vibration remain as fallback if audio routing is unavailable.
        }
    }

    private func toneURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lockedin-rest-alert.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let sampleRate = 44_100
        let duration = 0.65
        let sampleCount = Int(Double(sampleRate) * duration)
        let frequency = 880.0
        var pcm = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleRate)
            let envelope = min(1.0, min(t / 0.03, (duration - t) / 0.08))
            let value = sin(2.0 * .pi * frequency * t) * max(0, envelope) * 0.55
            var sample = Int16(max(-1, min(1, value)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }

        var data = Data()
        func appendASCII(_ value: String) { data.append(value.data(using: .ascii)!) }
        func appendUInt16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + pcm.count))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(pcm.count))
        data.append(pcm)

        try data.write(to: url, options: .atomic)
        return url
    }
}
