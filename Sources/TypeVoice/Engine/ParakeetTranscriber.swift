import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v2 (English) on CoreML / Neural Engine via FluidAudio.
actor ParakeetTranscriber: Transcriber {
    private var manager: AsrManager?
    private var warming: Task<Void, Error>?
    private let version: AsrModelVersion = .v2

    var isReady: Bool { manager != nil }

    /// Where FluidAudio caches the CoreML bundles for this model version.
    nonisolated var cacheDirectory: URL { AsrModels.defaultCacheDirectory(for: .v2) }

    nonisolated var isDownloaded: Bool { AsrModels.modelsExist(at: cacheDirectory) }

    func warm(progress: @escaping @Sendable (WarmProgress) -> Void) async throws {
        if manager != nil { progress(.init(phase: .ready, fraction: 1)); return }
        if let warming { try await warming.value; return }

        let task = Task<Void, Error> {
            let t0 = ContinuousClock.now
            progress(.init(phase: .checking, fraction: 0))
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { p in
                    switch p.phase {
                    case .listing:
                        progress(.init(phase: .checking, fraction: p.fractionCompleted))
                    case .downloading:
                        progress(.init(phase: .downloading, fraction: p.fractionCompleted))
                    case .compiling:
                        progress(.init(phase: .compiling, fraction: p.fractionCompleted))
                    }
                }
            )
            progress(.init(phase: .loading, fraction: 0))
            // v2's blank id up front, and no seam-gap repair: that pass re-decodes around any
            // pause ≥ 1.5 s in recordings over 15 s (a thinking pause, for a dictation) and on
            // this speaker's recordings it changed nothing while adding ~300 ms.
            let m = AsrManager(config: ASRConfig(tdtConfig: TdtConfig(blankId: 1024), seamGapRepair: false))
            try await m.loadModels(models)
            self.manager = m
            Log.timing("asr.warm", since: t0)
            Log.asr.info("Parakeet \(String(describing: self.version)) ready")
            Log.d("parakeet ready in \(Int((ContinuousClock.now - t0).ms)) ms")
            progress(.init(phase: .ready, fraction: 1))
        }
        warming = task
        defer { warming = nil }
        try await task.value
    }

    func transcribe(_ samples: [Float]) async throws -> Transcript {
        guard let manager else { throw TranscriberError.notReady }
        let t0 = ContinuousClock.now
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)
        Log.timing("asr.transcribe", since: t0)
        Log.asr.debug("asr \(String(format: "%.0f", result.duration * 1000))ms audio → \(String(format: "%.0f", result.processingTime * 1000))ms, conf \(result.confidence)")
        let tokens = (result.tokenTimings ?? []).map { Transcript.Token(token: $0.token, start: $0.startTime, end: $0.endTime, confidence: $0.confidence) }
        return Transcript(text: result.text, tokens: tokens)
    }

    enum TranscriberError: LocalizedError {
        case notReady
        var errorDescription: String? { "Speech model is still loading." }
    }
}
