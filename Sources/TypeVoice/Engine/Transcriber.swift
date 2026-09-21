import Foundation

/// What the app needs from a speech engine. Kept minimal so the engine can be
/// swapped (or streamed) without touching the rest of the pipeline.
protocol Transcriber: Sendable {
    /// Download/compile/load. Safe to call more than once.
    func warm(progress: @escaping @Sendable (WarmProgress) -> Void) async throws
    var isReady: Bool { get async }
    /// 16 kHz mono Float32 samples in, text out. Punctuated and cased.
    func transcribe(_ samples: [Float]) async throws -> Transcript
}

struct Transcript: Sendable {
    var text: String
    /// Per-token timings when the engine provides them (SentencePiece pieces, ▁ marks a word start),
    /// with the model's own confidence in each piece (0…1).
    var tokens: [Token]
    struct Token: Sendable { var token: String; var start: TimeInterval; var end: TimeInterval; var confidence: Float }
}

struct WarmProgress: Sendable, Equatable {
    enum Phase: Sendable, Equatable { case checking, downloading, compiling, loading, ready }
    var phase: Phase
    var fraction: Double   // 0…1 within the phase

    var label: String {
        switch phase {
        case .checking: return "Checking…"
        case .downloading: return "Downloading model…"
        case .compiling: return "Warming up, once…"
        case .loading: return "Loading…"
        case .ready: return "Ready"
        }
    }
}
