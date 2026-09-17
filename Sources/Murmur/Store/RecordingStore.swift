import AVFoundation
import Foundation

/// Opt-in: keeps each dictation's audio as a small AAC file next to the history,
/// so it can be dragged into a chat by people who'd rather send their voice.
enum RecordingStore {
    static let folder: URL = {
        let dir = Paths.support.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Encodes 16 kHz mono samples to AAC (~32 kbps). Returns the file URL.
    static func save(samples: [Float], id: UUID) throws -> URL {
        let url = folder.appendingPathComponent("\(id.uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let chunk = 16_000
        var i = 0
        while i < samples.count {
            let n = min(chunk, samples.count - i)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
            buf.frameLength = AVAudioFrameCount(n)
            samples.withUnsafeBufferPointer { p in
                buf.floatChannelData![0].update(from: p.baseAddress! + i, count: n)
            }
            try file.write(from: buf)
            i += n
        }
        return url
    }

    static func url(for id: UUID) -> URL? {
        let u = folder.appendingPathComponent("\(id.uuidString).m4a")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static func delete(id: UUID) {
        if let u = url(for: id) { try? FileManager.default.removeItem(at: u) }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Total size on disk, for the Privacy page.
    static func totalBytes() -> Int64 {
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

/// Plays one recording at a time.
@MainActor
final class RecordingPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = RecordingPlayer()
    private var player: AVAudioPlayer?
    private(set) var playingID: UUID?
    var onChange: (() -> Void)?

    func toggle(id: UUID) {
        if playingID == id { stop(); return }
        guard let url = RecordingStore.url(for: id) else { return }
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
        playingID = id
        onChange?()
        NotificationCenter.default.post(name: .murmurPlaybackChanged, object: nil)
    }

    func stop() {
        player?.stop(); player = nil; playingID = nil; onChange?()
        NotificationCenter.default.post(name: .murmurPlaybackChanged, object: nil)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

extension Notification.Name {
    static let murmurPlaybackChanged = Notification.Name("murmur.playbackChanged")
}
