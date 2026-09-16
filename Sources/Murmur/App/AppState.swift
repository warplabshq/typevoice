import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case idle
        case listening(locked: Bool)
        case processing
        case done(String)
        case notHeard
        case error(String)

        var isListening: Bool { if case .listening = self { return true } else { return false } }
        var isActive: Bool { self != .idle }
    }

    var phase: Phase = .idle
    /// Ring of recent loudness samples (0…1), newest last. Drives the waveform.
    var levels: [Float] = Array(repeating: 0, count: 40)
    var paused = false
    var warm: WarmProgress = .init(phase: .checking, fraction: 0)
    var isReady: Bool { warm.phase == .ready }
    var warmError: String?
    var accessibilityMissing = false
    var smartCleanupAvailable = false

    func pushLevel(_ l: Float) {
        levels.removeFirst()
        levels.append(l)
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: levels.count)
    }
}
