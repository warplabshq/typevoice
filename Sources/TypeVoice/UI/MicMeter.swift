import AVFoundation
import SwiftUI

/// Live input level for the chosen microphone, only while visible.
struct MicMeter: View {
    let deviceUID: String
    @State private var level: Float = 0
    @State private var peak: Float = 0
    @State private var engine: AVAudioEngine?
    @State private var error: String?
    @State private var stopTask: Task<Void, Never>?
    private var testing: Bool { engine != nil }

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
        let e = AVAudioEngine()
        let input = e.inputNode
        if let dev = InputDevices.resolve(preference: deviceUID), let unit = input.audioUnit {
            var id = dev.id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0 else { error = "No input"; return }
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buf, _ in
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
        do { try e.start(); engine = e; error = nil } catch { self.error = error.localizedDescription }
    }

    private func stop() {
        stopTask?.cancel(); stopTask = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0; peak = 0
    }
}
