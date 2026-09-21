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
    /// The format the converter and the spectrum were built for. AirPods and other Bluetooth
    /// mics change the input format under us (48 kHz → 24 kHz when they switch to their headset
    /// profile), so both are rebuilt from the buffer that actually arrives.
    private var inFormat: AVAudioFormat?
    private var outFormat: AVAudioFormat
    private var tapInstalled = false
    private(set) var isRunning = false
    private var configObserver: Any?

    static let sampleRate: Double = 16_000

    init() {
        outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false)!
        // The engine says so itself when a device or its format changes; the next start must
        // rebuild the graph instead of taping over a stale one (that raised an Objective-C
        // exception inside installTap, which no Swift `catch` can see, and left dictation dead).
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.needsReset = true
            // Choosing the device at start posts one of these too, a moment later; only a change
            // well into a session counts as an interruption.
            if self.isRunning, Date().timeIntervalSince(self.startedAt) > 1.0, let onInterrupted = self.onInterrupted {
                Task { @MainActor in onInterrupted() }
            }
        }
    }
    private var needsReset = false
    private var startedAt = Date.distantPast

    func start() throws {
        guard !isRunning else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true); peak = 0 }

        let input = engine.inputNode
        // The Mac's own mic unless the person chose otherwise (see InputDevices.resolve).
        if let dev = InputDevices.resolve(preference: Prefs.inputDeviceUID), let unit = input.audioUnit {
            var id = dev.id
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { Log.audio.warning("could not select input \(dev.name): \(status)") }
        }
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw RecorderError.noInput
        }
        Log.d("mic: \(Self.currentInputName() ?? Self.defaultInputName() ?? "?") \(Int(inFormat.sampleRate)) Hz ×\(inFormat.channelCount)")

        if tapInstalled { input.removeTap(onBus: 0); tapInstalled = false }
        if needsReset { engine.stop(); engine.reset(); needsReset = false }
        // `format: nil` taps whatever the node produces right now; a format of our own that
        // disagrees with the hardware raises an uncatchable exception.
        input.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // A mic that just vanished, or a headset mid-switch: one retry on the Mac's own mic,
            // so the person keeps their sentence instead of an error.
            Log.d("mic start failed (\(error.localizedDescription)); retrying on the built-in mic")
            input.removeTap(onBus: 0); tapInstalled = false
            engine.stop(); engine.reset()
            if let dev = InputDevices.builtIn(), let unit = input.audioUnit {
                var id = dev.id
                AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
            input.installTap(onBus: 0, bufferSize: 512, format: nil) { [weak self] buffer, _ in self?.consume(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
        }
        startedAt = Date()
        isRunning = true
    }

    /// Called on the main actor if the input device changes or disappears mid-session
    /// (AirPods taken off, a USB mic unplugged). The controller finishes with what it has.
    var onInterrupted: (@MainActor () -> Void)?

    /// The converter and the spectrum follow the buffers' real format, whatever the mic became.
    private func prepare(for format: AVAudioFormat) {
        guard inFormat == nil || inFormat! != format else { return }
        inFormat = format
        converter = AVAudioConverter(from: format, to: outFormat)
        converter?.sampleRateConverterQuality = .max
        spectrum = Spectrum(bands: 10, sampleRate: format.sampleRate)
        Log.d("mic format: \(Int(format.sampleRate)) Hz ×\(format.channelCount)")
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
        prepare(for: buffer.format)
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

    /// The microphone a session records from: the chosen one if it's connected, else the default.
    static func currentInputName() -> String? {
        if let dev = InputDevices.resolve(preference: Prefs.inputDeviceUID) { return dev.name }
        return defaultInputName()
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
