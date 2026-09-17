import AppKit
import Foundation

/// Hold → record → transcribe → clean → insert. Owns every stage's lifecycle
/// and is the only thing that mutates `AppState.phase`.
@MainActor
final class DictationController {
    let state: AppState
    let history: HistoryStore
    let dictionary: DictionaryStore
    let hotkey = HotkeyMonitor()
    let recorder = AudioRecorder()
    let transcriber: any Transcriber = ParakeetTranscriber()
    let smart = SmartCleaner()
    let inserter = TextInserter()
    var hud: HUDController?
    var licensing: Licensing?

    private var target: TextInserter.Target?
    private var locked = false
    private var pressStart: ContinuousClock.Instant?
    private var lockWindow: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var dismiss: Task<Void, Never>?
    private var levelSmoother: Float = 0

    static let doubleTapWindow: Duration = .milliseconds(380)
    static let shortHold: Duration = .milliseconds(300)
    static let minSpeech: Double = 0.35         // seconds
    static let minPeak: Float = 0.004            // raw amplitude, ≈ -48 dBFS; Parakeet is the real judge

    init(state: AppState, history: HistoryStore, dictionary: DictionaryStore) {
        self.state = state
        self.history = history
        self.dictionary = dictionary
        recorder.onLevel = { [weak self] l in
            Task { @MainActor in self?.level(l) }
        }
        recorder.onBands = { [weak self] b in
            Task { @MainActor in
                guard let self, self.state.phase.isListening else { return }
                self.state.bands = b
            }
        }
        hotkey.onPress = { [weak self] in self?.press() }
        hotkey.onRelease = { [weak self] in self?.release() }
        hotkey.onEscape = { [weak self] in self?.cancel() }
        hotkey.onChord = { [weak self] in
            // ⌘C while holding ⌘ as the trigger: not a dictation. Drop it quietly.
            guard let self, self.state.phase.isListening, !self.locked else { return }
            self.cancel()
        }
        watchActive()
    }

    /// Keep the tap thread's "session active" flag in sync with the phase.
    private func watchActive() {
        withObservationTracking {
            hotkey.setActive(state.phase.isActive)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchActive() }
        }
    }

    func start() {
        hotkey.start()
        state.accessibilityMissing = !Permissions.accessibility
        watchAccessibility()
        warm()
        state.smartCleanupAvailable = smart.isAvailable
        if smart.isAvailable { smart.prewarm() }
    }

    func restartHotkey() { hotkey.start() }

    private var axWatcher: Task<Void, Never>?

    /// If Accessibility is missing or gets revoked, keep checking and reinstall
    /// the hotkey the moment it's back. Cheap: one bool every 2 s.
    private func watchAccessibility() {
        axWatcher?.cancel()
        axWatcher = Task { @MainActor [weak self] in
            var last = Permissions.accessibility
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let now = Permissions.accessibility
                if now != last {
                    last = now
                    self.state.accessibilityMissing = !now
                    Log.d("accessibility changed → \(now); reinstalling hotkey")
                    self.hotkey.start()
                }
            }
        }
    }

    func warm() {
        state.warmError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                try await transcriber.warm { [weak self] p in
                    Task { @MainActor in self?.state.warm = p }
                }
            } catch {
                self.state.warmError = error.localizedDescription
                Log.asr.error("warm failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Key events

    private func press() {
        guard !state.paused else { return }
        if let licensing, licensing.isExpired, state.phase == .idle {
            hud?.present(for: inserter.captureTarget())
            show(.error("Trial ended · open \(Brand.name) to continue"), for: .milliseconds(2200))
            openMainWindow(.license)
            return
        }
        let now = ContinuousClock.now

        // Second tap inside the window → lock hands-free.
        if lockWindow != nil, state.phase.isListening {
            lockWindow?.cancel(); lockWindow = nil
            locked = true
            state.phase = .listening(locked: true)
            return
        }
        // Tap while locked → finish.
        if locked, state.phase.isListening {
            finish()
            return
        }
        guard state.phase == .idle else { return }

        pressStart = now
        dismiss?.cancel()
        target = inserter.captureTarget()
        state.resetLevels()
        levelSmoother = 0
        do {
            try recorder.start()
        } catch {
            show(.error(error.localizedDescription), for: .milliseconds(1400))
            return
        }
        locked = false
        state.listeningSince = .now
        state.phase = .listening(locked: false)
        hud?.present(for: target)
        Log.app.info("listening → \(self.target?.appName ?? "?")")
        Log.d("listening → \(target?.appName ?? "?")")
    }

    private func release() {
        guard state.phase.isListening, !locked else { return }
        let held = pressStart.map { ContinuousClock.now - $0 } ?? .seconds(0)
        if held < Self.shortHold {
            // Might be the first half of a double-tap: keep recording briefly.
            lockWindow = Task { [weak self] in
                try? await Task.sleep(for: Self.doubleTapWindow)
                guard let self, !Task.isCancelled else { return }
                self.lockWindow = nil
                self.finish()
            }
            return
        }
        finish()
    }

    func cancel() {
        lockWindow?.cancel(); lockWindow = nil
        finishTask?.cancel(); finishTask = nil
        recorder.cancel()
        locked = false
        state.phase = .idle
        hud?.dismiss()
        Log.app.info("cancelled")
    }

    // MARK: Pipeline

    /// Debug: run a full session with audio from a file instead of the microphone.
    func simulate(wav: URL) {
        guard state.phase == .idle, let samples = try? PipelineTest.load16k(wav) else { return }
        target = inserter.captureTarget()
        state.resetLevels()
        state.listeningSince = .now
        state.phase = .listening(locked: false)
        hud?.present(for: target)
        Task { @MainActor in
            for i in 0..<60 {
                state.bands = DemoBands.at(Double(i) * 0.05)
                try? await Task.sleep(for: .milliseconds(50))
            }
            finish(with: AudioRecorder.Recording(samples: samples, peak: 0.5))
        }
    }

    private func finish() {
        guard state.phase.isListening else { return }
        let rec = recorder.stop()
        finish(with: rec)
    }

    private func finish(with rec: AudioRecorder.Recording) {
        guard state.phase.isListening else { return }
        let t0 = ContinuousClock.now
        locked = false
        state.phase = .processing

        guard rec.seconds >= Self.minSpeech, rec.peak >= Self.minPeak else {
            Log.d("not heard: \(String(format: "%.2f", rec.seconds))s peak=\(rec.peak)")
            show(.notHeard, for: .milliseconds(900))
            return
        }
        let target = self.target
        finishTask = Task { [weak self] in
            guard let self else { return }
            var produced: String?
            do {
                let ready = await transcriber.isReady
                if !ready {
                    // Model still loading: wait for it rather than losing the audio.
                    try await transcriber.warm { [weak self] p in Task { @MainActor in self?.state.warm = p } }
                }
                let transcript = try await transcriber.transcribe(rec.samples)
                try Task.checkCancellation()
                var raw = transcript.text
                Log.asr.info("raw: \(raw)")
                Log.d("raw(\(String(format: "%.1f", rec.seconds))s): \(raw)")

                // Paragraphs from real pauses (≥ 1 s after a sentence end), using word timings.
                if Prefs.pauseParagraphs, !transcript.tokens.isEmpty {
                    raw = Structure.paragraphs(Structure.words(text: raw, tokens: transcript.tokens), pause: 1.0)
                }
                let style = Style.current
                var text = Cleaner.clean(raw, style: style)
                if Prefs.voiceCommands { text = Structure.commands(text) }
                if Prefs.numbersAsDigits { text = Numbers.apply(text) }
                text = Vocabulary.apply(dictionary.terms, to: text)
                if Prefs.smartCleanup {
                    smart.style = style
                    smart.dictionary = dictionary.terms
                    if let better = await smart.clean(text) {
                        text = Vocabulary.apply(dictionary.terms, to: better)
                    }
                }
                text = style.finish(text)
                text = Cleaner.fit(text, to: .unknown, style: style)
                if Prefs.leadingSpace, let f = text.first, !f.isWhitespace, !f.isPunctuation { text = " " + text }
                produced = text.trimmingCharacters(in: .whitespaces)
                try Task.checkCancellation()

                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                    show(.notHeard, for: .milliseconds(900)); return
                }

                guard let target else { throw TextInserter.InsertError.noFocusedApp }
                guard inserter.hasTextTarget(target) else {
                    Log.d("no text target in \(target.appName); offering copy")
                    let entry = Dictation(text: text.trimmingCharacters(in: .whitespaces), date: .now, appName: target.appName,
                                          bundleID: target.bundleID, seconds: rec.seconds, latencyMs: Int((ContinuousClock.now - t0).ms))
                    history.add(entry)
                    if Prefs.keepRecordings { let samples = rec.samples; _ = try? RecordingStore.save(samples: samples, id: entry.id) }
                        show(.copyOffer(text.trimmingCharacters(in: .whitespaces), copied: false), for: .seconds(8))
                    return
                }
                let method = try await inserter.insert(text, into: target)
                Log.timing("total.release_to_insert", since: t0)
                Log.insert.info("inserted via \(method.rawValue) into \(target.appName)")
                Log.d("inserted via \(method.rawValue) into \(target.appName): \(text)")

                let latency = Int((ContinuousClock.now - t0).ms)
                let entry = Dictation(text: text.trimmingCharacters(in: .whitespaces), date: .now, appName: target.appName,
                                      bundleID: target.bundleID, seconds: rec.seconds, latencyMs: latency)
                history.add(entry)
                state.lastAudio = nil
                if Prefs.keepRecordings {
                    let samples = rec.samples
                    let url = try? await Task.detached(priority: .utility) { try RecordingStore.save(samples: samples, id: entry.id) }.value
                    state.lastAudio = url
                }
                if Prefs.showPreview || state.lastAudio != nil {
                    // With an audio chip, linger long enough to grab it.
                    let ms = state.lastAudio != nil ? 6000 : min(2600, 700 + text.count * 12)
                    show(.done(Prefs.showPreview ? text.trimmingCharacters(in: .whitespaces) : ""), for: .milliseconds(ms))
                } else {
                    // Nothing to say: retreat into the edge right away.
                    state.phase = .idle
                    hud?.dismiss()
                }
            } catch is CancellationError {
                // cancelled by user
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Log.insert.error("insert failed: \(msg)")
                Log.d("FAILED: \(msg)")
                if let produced, !produced.isEmpty {
                    inserter.copyToClipboard(produced)
                    show(.error(msg + ". Copied instead."), for: .milliseconds(1600))
                } else {
                    show(.error(msg), for: .milliseconds(1400))
                }
            }
        }
    }

    /// Called from the pill's Copy button.
    func copyOffered() {
        guard case .copyOffer(let text, _) = state.phase else { return }
        inserter.copyToClipboard(text)
        show(.copyOffer(text, copied: true), for: .milliseconds(900))
    }

    private func show(_ phase: AppState.Phase, for d: Duration) {
        state.phase = phase
        dismiss?.cancel()
        dismiss = Task { [weak self] in
            try? await Task.sleep(for: d)
            guard let self, !Task.isCancelled else { return }
            if self.state.phase == phase {
                self.state.phase = .idle
                self.hud?.dismiss()
            }
        }
    }

    private func level(_ raw: Float) {
        // Fast attack, slower release so the waveform feels alive but not jittery.
        levelSmoother = raw > levelSmoother ? raw * 0.6 + levelSmoother * 0.4 : raw * 0.2 + levelSmoother * 0.8
        if state.phase.isListening { state.pushLevel(levelSmoother) }
    }

}
