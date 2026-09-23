import AudioToolbox
import Foundation

/// The second way to hear the microphone. AVAudioEngine drives input and output together, and on
/// some Macs it won't start at all (error -10868, "format not supported"), typically while a
/// Bluetooth headset holds the output at a rate the built-in mic doesn't share. An input-only
/// AudioQueue doesn't care about the output side, and converts whatever the device delivers
/// into the 16 kHz mono Float32 we ask for.
final class QueueInput: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    private var queue: AudioQueueRef?
    private let callbackQueue = DispatchQueue(label: "typevoice.queueinput", qos: .userInteractive)
    private let onSamples: (UnsafePointer<Float>, Int) -> Void

    init(onSamples: @escaping (UnsafePointer<Float>, Int) -> Void) { self.onSamples = onSamples }

    /// `deviceUID` nil: whatever input macOS is using.
    func start(deviceUID: String?) throws {
        var fmt = AudioStreamBasicDescription(
            mSampleRate: Self.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var q: AudioQueueRef?
        var status = AudioQueueNewInputWithDispatchQueue(&q, &fmt, 0, callbackQueue) { [weak self] queue, buffer, _, _, _ in
            let n = Int(buffer.pointee.mAudioDataByteSize) / MemoryLayout<Float>.size
            if n > 0, let self {
                self.onSamples(buffer.pointee.mAudioData.assumingMemoryBound(to: Float.self), n)
            }
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
        guard status == noErr, let q else { throw Failure(status: status, step: "new") }
        if let uid = deviceUID {
            var cf = uid as CFString
            status = withUnsafePointer(to: &cf) {
                AudioQueueSetProperty(q, kAudioQueueProperty_CurrentDevice, $0, UInt32(MemoryLayout<CFString>.size))
            }
            if status != noErr { Log.d("queue input: couldn't select \(uid) (\(status)); using the system input") }
        }
        let bytes = UInt32(Self.sampleRate / 50) * 4          // 20 ms per buffer
        for _ in 0..<4 {
            var b: AudioQueueBufferRef?
            guard AudioQueueAllocateBuffer(q, bytes, &b) == noErr, let b else { continue }
            AudioQueueEnqueueBuffer(q, b, 0, nil)
        }
        status = AudioQueueStart(q, nil)
        guard status == noErr else { AudioQueueDispose(q, true); throw Failure(status: status, step: "start") }
        queue = q
    }

    func stop() {
        guard let q = queue else { return }
        AudioQueueStop(q, true)
        AudioQueueDispose(q, true)
        queue = nil
    }

    var isRunning: Bool { queue != nil }

    struct Failure: LocalizedError {
        let status: OSStatus, step: String
        var errorDescription: String? { "The microphone couldn't start (\(step) \(status))." }
    }
}
