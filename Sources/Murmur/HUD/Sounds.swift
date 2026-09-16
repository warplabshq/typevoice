import AVFoundation

/// Two tiny synthesised tones. No asset files, no latency surprises.
final class Sounds {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var startTone = Self.tone(from: 540, to: 760, seconds: 0.11, gain: 0.16)
    private lazy var doneTone = Self.tone(from: 760, to: 520, seconds: 0.13, gain: 0.15)

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
    }

    func start() { play(startTone) }
    func done() { play(doneTone) }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard Prefs.sounds else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { Log.audio.error("sound engine: \(error.localizedDescription)"); return }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private static func tone(from f0: Double, to f1: Double, seconds: Double, gain: Float) -> AVAudioPCMBuffer {
        let sr = 44_100.0
        let n = Int(sr * seconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        let p = buf.floatChannelData![0]
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let f = f0 + (f1 - f0) * (t * t * (3 - 2 * t))          // smoothstep glide
            phase += 2 * .pi * f / sr
            let attack = min(1, Double(i) / (sr * 0.006))
            let release = exp(-4.5 * t)
            let env = attack * release
            let s = sin(phase) + 0.25 * sin(2 * phase)
            p[i] = Float(s * env) * gain
        }
        return buf
    }
}
