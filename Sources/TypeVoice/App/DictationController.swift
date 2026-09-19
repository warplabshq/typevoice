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
    private var lengthCap: Task<Void, Never>?
    private var dismiss: Task<Void, Never>?
    private var levelSmoother: Float = 0

    static let doubleTapWindow: Duration = .milliseconds(380)
    static let shortHold: Duration = .milliseconds(300)
    static let minSpeech: Double = 0.35         // seconds
    static let minPeak: Float = 0.004            // raw amplitude, ≈ -48 dBFS; Parakeet is the real judge
    static let silentPeak: Float = 0.0005        // below this the mic is delivering nothing (muted, wrong device, no permission)
    /// Longest single dictation. Past this the words so far are typed; nobody wants an hour in one paste.
    static let maxSeconds: Double = 10 * 60

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
        Log.d("apple intelligence: \(SmartCleaner.status.title)")
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

        // Tap-to-toggle: a press while listening ends the session.
        if Prefs.triggerMode == .toggle, state.phase.isListening {
            finish()
            return
        }
        // Hold mode, second tap inside the window → lock hands-free.
        if Prefs.triggerMode == .hold, Prefs.doubleTapLock, lockWindow != nil, state.phase.isListening {
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
        // A press while the pill is still showing the last result starts a new session at once.
        switch state.phase {
        case .idle: break
        case .done, .notHeard, .error, .copyOffer:
            dismiss?.cancel()
            state.phase = .idle
        default:
            return
        }

        pressStart = now
        finishTask?.cancel(); finishTask = nil
        state.lastAudio = nil
        target = inserter.captureTarget()
        state.resetLevels()
        levelSmoother = 0
        do {
            try recorder.start()
        } catch {
            Log.d("mic start failed: \(error.localizedDescription)")
            hud?.present(for: target)
            show(.error(error.localizedDescription), for: .milliseconds(1400))
            return
        }
        locked = Prefs.triggerMode == .toggle          // toggle mode is hands-free by nature
        state.listeningSince = .now
        state.phase = .listening(locked: locked)
        lengthCap?.cancel()
        lengthCap = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxSeconds))
            guard let self, !Task.isCancelled, self.state.phase.isListening else { return }
            Log.app.info("length cap reached; finishing")
            self.lockWindow?.cancel(); self.lockWindow = nil
            self.finish()
        }
        hud?.present(for: target)
        Log.app.info("listening → \(self.target?.appName ?? "?")")
        Log.d("listening → \(target?.appName ?? "?") ax=\(target?.element != nil) ctx=\(target?.context.textBeforeCaret?.suffix(20).description ?? "nil")")
    }

    private func release() {
        guard Prefs.triggerMode == .hold else { return }   // toggle mode ignores key-up
        guard state.phase.isListening, !locked else { return }
        let held = pressStart.map { ContinuousClock.now - $0 } ?? .seconds(0)
        if Prefs.doubleTapLock, held < Self.shortHold {
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
        lengthCap?.cancel(); lengthCap = nil
        finishTask?.cancel(); finishTask = nil
        recorder.cancel()
        locked = false
        state.processingNote = nil
        state.phase = .idle
        hud?.dismiss()
        Log.app.info("cancelled")
    }

    // MARK: Remote control (typevoice:// URLs, for Shortcuts, Raycast, Stream Deck…)

    /// Starts a hands-free session as if the trigger had been double-tapped.
    func startHandsFree() {
        guard state.phase == .idle || !state.phase.isListening else { return }
        press()
        guard state.phase.isListening else { return }
        lockWindow?.cancel(); lockWindow = nil
        locked = true
        state.phase = .listening(locked: true)
    }

    /// Ends the session and types the words; nothing happens if none is running.
    func stopAndType() {
        lockWindow?.cancel(); lockWindow = nil
        finish()
    }

    func toggle() {
        if state.phase.isListening { stopAndType() } else { startHandsFree() }
    }

    // MARK: Pipeline

    /// Debug: put the pill in a state by name — listening, locked, processing, done, copy,
    /// error, notheard, audio, idle — for design review. No audio, no insertion.
    func preview(_ name: String) {
        dismiss?.cancel(); finishTask?.cancel(); finishTask = nil
        target = inserter.captureTarget()
        state.resetLevels()
        let sample = "Can we move the launch review to Wednesday at three? I want the changelog in first."
        switch name {
        case "listening", "locked":
            state.listeningSince = .now
            state.phase = .listening(locked: name == "locked")
            Task { @MainActor [weak self] in
                var i = 0
                while let self, self.state.phase.isListening, i < 6000 {
                    self.state.bands = DemoBands.at(Double(i) * 0.05); i += 1
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        case "processing": state.phase = .processing
        case "done": state.phase = .done(sample)
        case "audio":
            state.lastAudioName = RecordingStore.fileName(for: sample)
            state.lastAudio = try? RecordingStore.save(samples: [Float](repeating: 0, count: 16_000), id: UUID())
            state.phase = .done(sample)
        case "copy": state.phase = .copyOffer(sample, copied: false)
        case "copied": state.phase = .copyOffer(sample, copied: true)
        case "error": state.phase = .error("Can't type into a password field. Copied instead.")
        case "notheard": state.phase = .notHeard(silent: false)
        case "silent": state.phase = .notHeard(silent: true)
        default:
            state.lastAudio = nil
            state.phase = .idle; hud?.dismiss(); return
        }
        hud?.present(for: target)
    }

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
        lengthCap?.cancel(); lengthCap = nil
        let t0 = ContinuousClock.now
        locked = false
        state.phase = .processing

        guard rec.seconds >= Self.minSpeech, rec.peak >= Self.minPeak else {
            Log.d("not heard: \(String(format: "%.2f", rec.seconds))s peak=\(rec.peak)")
            // A held key with a flat line is a mic problem, not a mumble: say so, and offer Settings.
            let silent = rec.seconds >= 1.0 && rec.peak < Self.silentPeak
            show(.notHeard(silent: silent), for: .milliseconds(silent ? 4000 : 900))
            return
        }
        let target = self.target
        finishTask = Task { [weak self] in
            guard let self else { return }
            var produced: String?
            do {
                if !(await transcriber.isReady) {
                    // Model still loading: keep the audio and wait, but stay cancellable (Esc or the
                    // pill's ×) and give up after a while rather than sit on a frozen pill.
                    state.processingNote = "Loading the speech model…"
                    let deadline = ContinuousClock.now + .seconds(90)
                    while !(await transcriber.isReady) {
                        try Task.checkCancellation()
                        if let e = state.warmError { throw StuckError.model(e) }
                        if ContinuousClock.now > deadline { throw StuckError.tooLong }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    state.processingNote = nil
                }
                let samples = rec.samples
                let transcript = try await Self.within(.seconds(30)) { try await self.transcriber.transcribe(samples) }
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
                let context = Prefs.insertion == .auto ? (target?.context ?? .unknown) : .unknown
                text = Cleaner.fit(text, to: context, style: style)
                // Blind paste (no readable field): Mac text views add the space themselves; web apps may not.
                if context.textBeforeCaret == nil, Prefs.leadingSpace, let f = text.first, !f.isWhitespace, !f.isPunctuation { text = " " + text }
                produced = text.trimmingCharacters(in: .whitespaces)
                try Task.checkCancellation()

                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                    show(.notHeard(silent: false), for: .milliseconds(900)); return
                }

                guard let target else { throw TextInserter.InsertError.noFocusedApp }
                guard inserter.hasTextTarget(target) else {
                    Log.d("no text target in \(target.appName); offering copy")
                    let entry = Dictation(text: text.trimmingCharacters(in: .whitespaces), date: .now, appName: target.appName,
                                          bundleID: target.bundleID, seconds: rec.seconds, latencyMs: Int((ContinuousClock.now - t0).ms))
                    history.add(entry)
                    if Prefs.keepRecordings, let url = try? RecordingStore.save(samples: RecordingStore.tightened(rec.samples), id: entry.id) { history.attachAudio(id: entry.id, url: url) }
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
                    let url = try? await Task.detached(priority: .utility) { try RecordingStore.save(samples: RecordingStore.tightened(samples), id: entry.id) }.value
                    state.lastAudioName = RecordingStore.fileName(for: entry.text)
                    state.lastAudio = url
                    if let url { history.attachAudio(id: entry.id, url: url) }
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

    /// The × on the pill: retreat now instead of waiting out the linger. While the words are
    /// still being worked on it is a stop button: the transcription is abandoned.
    func putAway() {
        if state.phase == .processing { cancel(); return }
        dismiss?.cancel()
        state.lastAudio = nil
        state.phase = .idle
        hud?.dismiss()
    }

    enum StuckError: LocalizedError {
        case tooLong
        case model(String)
        var errorDescription: String? {
            switch self {
            case .tooLong: return "Took too long. Try again"
            case .model(let e): return e
            }
        }
    }

    /// Runs `work` but gives up after `limit`. A CoreML call cannot be interrupted, so the
    /// work may finish later on its own; the session just stops waiting for it.
    static func within<T: Sendable>(_ limit: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { try await Task.sleep(for: limit); throw StuckError.tooLong }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    func copyOffered() {
        switch state.phase {
        case .copyOffer(let text, _):
            inserter.copyToClipboard(text)
            show(.copyOffer(text, copied: true), for: .milliseconds(900))
        case .done(let text) where !text.isEmpty:
            // The preview's copy glyph: grab the words without leaving the pill.
            inserter.copyToClipboard(text)
            dismiss?.cancel()
            show(.done(text), for: .seconds(4))
        default:
            break
        }
    }

    private func show(_ phase: AppState.Phase, for d: Duration) {
        state.processingNote = nil
        state.phase = phase
        dismiss?.cancel()
        dismiss = Task { [weak self] in
            try? await Task.sleep(for: d)
            // Someone is dragging the audio chip: keep the pill until they let go.
            while DragSourceView.isDragging, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
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
