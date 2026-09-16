import Foundation
import OSLog

/// One logger per subsystem area. `MURMUR_DEBUG=1` in the environment turns on
/// per-stage latency lines on stdout so `Tools/latency.sh` can parse them.
enum Log {
    static let app = Logger(subsystem: "com.priyam.murmur", category: "app")
    static let audio = Logger(subsystem: "com.priyam.murmur", category: "audio")
    static let asr = Logger(subsystem: "com.priyam.murmur", category: "asr")
    static let insert = Logger(subsystem: "com.priyam.murmur", category: "insert")
    static let hud = Logger(subsystem: "com.priyam.murmur", category: "hud")

    static let debugTimings = ProcessInfo.processInfo.environment["MURMUR_DEBUG"] == "1"

    /// Human-readable line on stderr when debugging is on (unified log needs FDA to read).
    static func d(_ msg: @autoclosure () -> String) {
        guard debugTimings else { return }
        FileHandle.standardError.write(("[murmur] " + msg() + "\n").data(using: .utf8)!)
    }

    /// Prints `stage=<name> ms=<n>` lines when debugging is on.
    static func timing(_ stage: String, since start: ContinuousClock.Instant) {
        guard debugTimings else { return }
        let ms = (ContinuousClock.now - start).ms
        print("stage=\(stage) ms=\(String(format: "%.1f", ms))")
    }
}

extension Duration {
    var ms: Double {
        let (s, atto) = components
        return Double(s) * 1000 + Double(atto) / 1e15
    }
}
