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

    /// The voice note nobody minds listening to: silence at either end is trimmed, and any
    /// pause longer than 1.5 s inside is shortened to 0.7 s. Words are untouched; only the
    /// dead air goes. The transcript is always made from the original samples.
    static func tightened(_ samples: [Float], sampleRate: Int = 16_000) -> [Float] {
        let frame = sampleRate / 50                       // 20 ms
        guard samples.count > frame * 10 else { return samples }
        // Per-frame RMS, then a floor from the quietest fifth of the frames plus a margin.
        var rms: [Float] = []
        rms.reserveCapacity(samples.count / frame + 1)
        var i = 0
        while i < samples.count {
            let n = min(frame, samples.count - i)
            var acc: Float = 0
            for j in i..<(i + n) { acc += samples[j] * samples[j] }
            rms.append((acc / Float(n)).squareRoot())
            i += n
        }
        let sorted = rms.sorted()
        let floor = sorted[sorted.count / 5]
        let loud = sorted[sorted.count * 4 / 5]
        // Well above the noise floor, but never so high that soft syllables count as silence.
        let gate = min(max(floor * 4, 0.003), max(loud / 6, 0.003))
        let speech = rms.map { $0 > gate }
        guard speech.contains(true) else { return samples }
        let keepPause = frame * 35                         // 0.7 s
        let longPause = frame * 75                         // 1.5 s
        let edge = frame * 12                              // 0.24 s of room around the first and last word
        let first = speech.firstIndex(of: true)!, last = speech.lastIndex(of: true)!
        var out: [Float] = []
        out.reserveCapacity(samples.count)
        var f = max(0, first - edge / frame)
        let end = min(rms.count, last + 1 + edge / frame)
        while f < end {
            if speech[f] {
                out.append(contentsOf: samples[(f * frame)..<min(samples.count, (f + 1) * frame)])
                f += 1
                continue
            }
            var g = f
            while g < end, !speech[g] { g += 1 }
            let run = (g - f) * frame
            if run > longPause {
                // Keep the head and tail of the pause so the cut is inaudible.
                let half = keepPause / 2
                out.append(contentsOf: samples[(f * frame)..<(f * frame + half)])
                out.append(contentsOf: samples[(g * frame - half)..<min(samples.count, g * frame)])
            } else {
                out.append(contentsOf: samples[(f * frame)..<min(samples.count, g * frame)])
            }
            f = g
        }
        return out
    }

    /// Encodes 16 kHz mono samples to AAC (~32 kbps). Returns the file URL.
    static func save(samples: [Float], id: UUID) throws -> URL {
        let url = folder.appendingPathComponent("\(id.uuidString).m4a")
        // AAC-LC in .m4a is the format everything plays — Messages, WhatsApp, Telegram, Slack,
        // mail, Windows, Android — and 32 kbps mono is plenty for speech (~240 KB a minute).
        // Constant bitrate, because a few strict players still misjudge VBR durations.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
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

    // MARK: Friendly names for sharing

    /// "Can we move the launch review.m4a": the first few words of what was said.
    /// Files stay stored by id; this only names what other apps receive.
    static func fileName(for text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).filter { $0.isLetter || $0.isNumber || $0 == "'" } }
            .filter { !$0.isEmpty }
        var name = ""
        for w in words {
            let next = name.isEmpty ? w : name + " " + w
            if next.count > 40 { break }
            name = next
            if name.split(separator: " ").count >= 6 { break }
        }
        if name.isEmpty { name = "Voice note" }
        return name.prefix(1).uppercased() + name.dropFirst() + ".m4a"
    }

    /// A hard link with the friendly name, for the drag pasteboard. Costs no disk space.
    /// It has to outlive the drag: WhatsApp reads the file in place, well after the drop.
    /// The folder is emptied on launch.
    static let dragFolder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Drag", isDirectory: true)
    }()

    static func dragLink(for url: URL, named name: String) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: dragFolder, withIntermediateDirectories: true)
        let link = dragFolder.appendingPathComponent(name)
        if fm.fileExists(atPath: link.path) {
            // Same recording already linked under this name? Reuse it.
            if let a = try? fm.attributesOfItem(atPath: link.path)[.systemFileNumber] as? Int,
               let b = try? fm.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int, a == b { return link }
            try? fm.removeItem(at: link)
        }
        do { try fm.linkItem(at: url, to: link) } catch {
            do { try fm.copyItem(at: url, to: link) } catch { return nil }
        }
        return link
    }

    static func cleanDragLinks() {
        try? FileManager.default.removeItem(at: dragFolder)
    }

    static func delete(id: UUID) {
        if let u = url(for: id) { try? FileManager.default.removeItem(at: u) }
    }

    /// Removes recordings older than the retention setting. The dictation stays in Summary;
    /// only its audio goes. Runs at launch and once a day after.
    static func prune(olderThanDays days: Int = Prefs.recordingDays) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        var n = 0
        for u in items where u.pathExtension == "m4a" {
            guard let c = try? u.resourceValues(forKeys: [.creationDateKey]).creationDate, c < cutoff else { continue }
            try? FileManager.default.removeItem(at: u); n += 1
        }
        if n > 0 { Log.app.info("pruned \(n) recordings older than \(days) days") }
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
        NotificationCenter.default.post(name: .typevoicePlaybackChanged, object: nil)
    }

    func stop() {
        player?.stop(); player = nil; playingID = nil; onChange?()
        NotificationCenter.default.post(name: .typevoicePlaybackChanged, object: nil)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

extension Notification.Name {
    static let typevoicePlaybackChanged = Notification.Name("typevoice.playbackChanged")
}
