import AVFoundation
import SwiftUI

/// Live input level for the chosen microphone, only while visible.
struct MicMeter: View {
    let deviceUID: String
    @State private var level: Float = 0
    @State private var peak: Float = 0
    @State private var engine: AVAudioEngine?
    @State private var queue: QueueInput?
    @State private var error: String?
    @State private var stopTask: Task<Void, Never>?
    private var testing: Bool { engine != nil || queue != nil }

    var body: some View {
        HStack(spacing: 10) {
            meter
            Button(testing ? "Stop" : "Test") { testing ? stop() : start() }
        }
        .onDisappear(perform: stop)
        .onChange(of: deviceUID) { _, _ in if testing { stop(); start() } }
    }

    private var meter: some View {
        VStack(alignment: .trailing, spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(level))
                        .animation(.linear(duration: 0.05), value: level)
                    Rectangle().fill(.primary.opacity(0.6)).frame(width: 2)
                        .offset(x: g.size.width * CGFloat(peak))
                        .animation(.easeOut(duration: 0.3), value: peak)
                }
            }
            .frame(width: 200, height: 8)
            .opacity(testing ? 1 : 0.5)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func start() {
        stopTask?.cancel()
        stopTask = Task { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { stop() } }
        // The chosen mic first; if the Mac's audio is in a state that input can't open in (a
        // headset mid-switch, mismatched rates: error -10868), whatever input macOS is using.
        var lastError: Error?
        for device in [InputDevices.resolve(preference: deviceUID), nil] as [InputDevices.Device?] {
            let e = AVAudioEngine()
            let input = e.inputNode
            if let dev = device, let unit = input.audioUnit {
                var id = dev.id
                AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
            guard input.outputFormat(forBus: 0).sampleRate > 0 else { continue }
            input.installTap(onBus: 0, bufferSize: 1024, format: AudioRecorder.tapFormat(input)) { buf, _ in
                guard let ch = buf.floatChannelData else { return }
                let n = Int(buf.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += ch[0][i] * ch[0][i] }
                let rms = (sum / Float(max(n, 1))).squareRoot()
                let db = 20 * log10(max(rms, 1e-6))
                let l = min(1, max(0, (db + 56) / 50))
                Task { @MainActor in
                    level = l
                    peak = max(l, peak * 0.97)
                }
            }
            e.prepare()
            do {
                try e.start(); engine = e
                error = device == nil && !deviceUID.isEmpty && deviceUID != InputDevices.followSystem ? "Showing the Mac's current input" : nil
                return
            } catch {
                lastError = error
                input.removeTap(onBus: 0); e.stop()
                Log.d("mic test: \(device?.name ?? "system input") failed: \(error.localizedDescription)")
            }
        }
        // AVAudioEngine won't start on this Mac right now: the input-only queue, like dictation.
        let q = QueueInput { p, n in
            var sum: Float = 0
            for i in 0..<n { sum += p[i] * p[i] }
            let db = 20 * log10(max((sum / Float(max(n, 1))).squareRoot(), 1e-6))
            let l = min(1, max(0, (db + 56) / 50))
            Task { @MainActor in level = l; peak = max(l, peak * 0.97) }
        }
        do {
            try q.start(deviceUID: InputDevices.resolve(preference: deviceUID)?.uid)
            queue = q; error = nil; return
        } catch {
            Log.d("mic test: queue input failed too: \(error.localizedDescription)")
        }
        self.error = lastError.map { _ in "Couldn't open the microphone. Try again, or pick another input." } ?? "No input"
    }

    private func stop() {
        stopTask?.cancel(); stopTask = nil
        queue?.stop(); queue = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0; peak = 0
    }
}
