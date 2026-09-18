import Foundation
import OSLog

/// One logger per subsystem area. `TYPEVOICE_DEBUG=1` in the environment turns on
/// per-stage latency lines on stdout so `Tools/latency.sh` can parse them.
enum Log {
    static let app = Logger(subsystem: "com.priyamventures.typevoice", category: "app")
    static let audio = Logger(subsystem: "com.priyamventures.typevoice", category: "audio")
    static let asr = Logger(subsystem: "com.priyamventures.typevoice", category: "asr")
    static let insert = Logger(subsystem: "com.priyamventures.typevoice", category: "insert")
    static let hud = Logger(subsystem: "com.priyamventures.typevoice", category: "hud")

    /// `TYPEVOICE_DEBUG=1` in the environment, or `defaults write com.priyamventures.typevoice debugLog -bool true`.
    static let debugTimings: Bool =
        ProcessInfo.processInfo.environment["TYPEVOICE_DEBUG"] == "1" || UserDefaults.standard.bool(forKey: "debugLog")

    /// ~/Library/Logs/TypeVoice/typevoice.log, also mirrored to stderr.
    static let logFile: FileHandle? = {
        guard debugTimings else { return nil }
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/TypeVoice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("typevoice.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    /// Human-readable line on stderr and in the log file when debugging is on.
    static func d(_ msg: @autoclosure () -> String) {
        guard debugTimings else { return }
        let stamp = ISO8601DateFormatter().string(from: .now)
        let line = "[\(stamp)] " + msg() + "\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
        logFile?.write(line.data(using: .utf8)!)
    }

    /// Prints `stage=<name> ms=<n>` lines when debugging is on.
    static func timing(_ stage: String, since start: ContinuousClock.Instant) {
        guard debugTimings else { return }
        let ms = (ContinuousClock.now - start).ms
        let line = "stage=\(stage) ms=\(String(format: "%.1f", ms))"
        print(line)
        logFile?.write((line + "\n").data(using: .utf8)!)
    }
}

extension Duration {
    var ms: Double {
        let (s, atto) = components
        return Double(s) * 1000 + Double(atto) / 1e15
    }
}
