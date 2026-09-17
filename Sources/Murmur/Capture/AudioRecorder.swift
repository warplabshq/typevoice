import AVFoundation
import CoreAudio
import Foundation

/// Microphone capture to 16 kHz mono Float32. The engine is kept allocated and
/// started only while a session runs, so the system mic indicator is honest.
final class AudioRecorder: @unchecked Sendable {
    /// Normalised 0…1 loudness, delivered on the audio thread ~50×/s.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Per-band energies 0…1 (low → high), same cadence.
    var onBands: (@Sendable ([Float]) -> Void)?
    private var spectrum: Spectrum?
    private var bandTick = 0

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var peak: Float = 0
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat
    private var tapInstalled = false
    private(set) var isRunning = false

    static let sampleRate: Double = 16_000

    init() {
        outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false)!
    }

    func start() throws {
        guard !isRunning else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true); peak = 0 }

        let input = engine.inputNode
        // Chosen microphone, if any and still connected; otherwise the system default.
        if let uid = Prefs.inputDeviceUID, let dev = InputDevices.device(uid: uid), let unit = input.audioUnit {
            var id = dev.id
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { Log.audio.warning("could not select input \(dev.name): \(status)") }
        }
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw RecorderError.noInput
        }
        converter = AVAudioConverter(from: inFormat, to: outFormat)
        converter?.sampleRateConverterQuality = .max
        spectrum = Spectrum(bands: 10, sampleRate: inFormat.sampleRate)
        Log.d("mic: \(Self.defaultInputName() ?? "?") \(Int(inFormat.sampleRate)) Hz ×\(inFormat.channelCount)")

        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 512, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stops capture and returns everything recorded since `start()`.
    func stop() -> Recording {
        guard isRunning else { return Recording(samples: [], peak: 0) }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
        engine.stop()
        isRunning = false
        return lock.withLock { Recording(samples: samples, peak: peak) }
    }

    /// Discards the current recording without returning it.
    func cancel() { _ = stop() }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let ch = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }

        // Level from the raw input (channel 0), before resampling.
        var sum: Float = 0
        var localPeak: Float = 0
        let p = ch[0]
        for i in 0..<n {
            let v = p[i]
            sum += v * v
            localPeak = max(localPeak, abs(v))
        }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        let lin = min(1, max(0, (db + 56) / 50))     // -56 dB … -6 dB → 0 … 1
        let level = pow(lin, 0.65)                    // lift quiet speech so the bars breathe
        onLevel?(level)
        if let spectrum {
            // Gate opens quickly once there is any signal above the noise floor.
            let gate = min(1, max(0, (db + 52) / 14))
            let bands = spectrum.analyze(p, count: n, gate: gate)
            // Analyse every buffer (keeps the smoothing honest) but deliver ~30×/s.
            bandTick += 1
            let every = max(1, Int((buffer.format.sampleRate / Double(n)) / 30))
            if bandTick % every == 0 { onBands?(bands) }
        }

        // Resample to 16 kHz mono.
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(n) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var delivered = false
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in
            if delivered { status.pointee = .noDataNow; return nil }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        if let error { Log.audio.error("convert: \(error.localizedDescription)"); return }
        let m = Int(out.frameLength)
        guard m > 0, let o = out.floatChannelData else { return }
        lock.withLock {
            samples.append(contentsOf: UnsafeBufferPointer(start: o[0], count: m))
            peak = max(peak, localPeak)
        }
    }

    /// Name of the system default input, for diagnostics.
    static func defaultInputName() -> String? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        var name: CFString = "" as CFString
        var nsize = UInt32(MemoryLayout<CFString>.size)
        var naddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &naddr, 0, nil, &nsize, &name) == noErr else { return nil }
        return name as String
    }

    struct Recording: Sendable {
        let samples: [Float]
        let peak: Float
        var seconds: Double { Double(samples.count) / AudioRecorder.sampleRate }
    }

    enum RecorderError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone input available." }
    }
}
