import AppKit
import SwiftUI

/// First-run setup, also reachable from the "?" toolbar button. Four cards that
/// check themselves off; the same visual language as the main window.
struct OnboardingView: View {
    let state: AppState
    var revisiting = false
    @State private var step = 0
    @State private var mic = Permissions.mic
    @State private var ax = Permissions.accessibility
    @State private var poll: Task<Void, Never>?
    @State private var askedAX: Date?
    @AppStorage(Prefs.Key.trigger) private var trigger = Prefs.Trigger.fn.rawValue

    private var steps: [String] { ["Microphone", "Accessibility", "Shortcut", "Model", "Try it"] }
    @State private var tryText = ""
    @State private var tried = false
    @FocusState private var tryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.top, 22)
                .padding(.bottom, 20)
            StepBar(titles: steps, current: step, done: [mic == .granted, ax, false, state.isReady, tried])
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            card
                .id(step)
                .transition(.blurFade)
                .padding(.horizontal, 32)
            Spacer(minLength: 16)
            footer
                .padding(.horizontal, 32)
                .padding(.bottom, 22)
        }
        .frame(width: 560, height: 540)
        .background(.background)
        .animation(Theme.springSoft, value: step)
        .onAppear(perform: startPolling)
        .onDisappear { poll?.cancel() }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            PillPreview(accent: Prefs.accent)
            Text("\(Brand.name)")
                .font(.system(size: 26, weight: .bold))
            Text("Just talk. It's typed. All on this Mac.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var card: some View {
        switch step {
        case 0:
            StepCard(
                icon: "mic.fill", title: "Microphone",
                text: "\(Brand.name) listens only while you hold your shortcut. Audio never leaves this Mac, and it is only kept if you later turn on the audio option.",
                done: mic == .granted,
                action: micAction
            )
        case 1:
            StepCard(
                icon: "hand.raised.fill", title: "Accessibility",
                text: axHint,
                done: ax,
                action: ("Allow accessibility", { askedAX = .now; Permissions.requestAccessibility(); Permissions.openAccessibilityPane() }),
                secondary: askedAX == nil ? nil : ("Relaunch \(Brand.name)", { Permissions.relaunch() })
            )
        case 2:
            StepCard(
                icon: "keyboard", title: "Your shortcut",
                text: trigger == Prefs.Trigger.fn.rawValue
                    ? "Hold 🌐 (the Globe/Fn key) to dictate. So macOS doesn't open the emoji picker every time, set “Press 🌐 key to” to Do Nothing in Keyboard settings."
                    : "Press what you want to hold: a key, a chord like ⌥⌘, or a combination like ⌥Space. Tap it twice to keep listening hands-free; Esc cancels.",
                done: false,
                action: trigger == Prefs.Trigger.fn.rawValue ? ("Open Keyboard settings", { Permissions.openKeyboardPane() }) : nil
            ) {
                Picker("Trigger", selection: $trigger) {
                    Text("🌐 Globe / Fn").tag(Prefs.Trigger.fn.rawValue)
                    Text("Custom").tag(Prefs.Trigger.custom.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                if trigger == Prefs.Trigger.custom.rawValue {
                    ShortcutRecorder()
                }
            }
        case 3:
            StepCard(
                icon: "cpu", title: "Speech model",
                text: state.warmError ?? (state.isReady
                    ? "Ready. Recognition runs on the Neural Engine; nothing is sent anywhere, ever."
                    : "The speech model is downloaded once, about 450 MB, then tuned for this Mac's Neural Engine. After this, dictation never needs the internet."),
                done: state.isReady,
                progress: state.isReady ? nil : state.warm,
                action: retryAction
            )
        default:
            StepCard(
                icon: tried ? "checkmark.seal.fill" : "waveform", title: tried ? "That's it" : "Say something",
                text: tried
                    ? "\(Brand.name) lives in your menu bar now (the small waveform, top right). Hold \(Prefs.triggerLabel) in any app to dictate. History, dictionary and settings are one click away."
                    : "Click the box below, hold \(Prefs.triggerLabel), say a sentence, and let go.",
                done: tried
            ) {
                TextField("Your words will land here", text: $tryText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(3...5)
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tryFocused ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: tryFocused ? 1.5 : 1))
                    .focused($tryFocused)
                    .onChange(of: tryText) { _, t in if !t.trimmingCharacters(in: .whitespaces).isEmpty { tried = true } }
                    .onAppear { tryFocused = true; NotificationCenter.default.post(name: .typevoiceArmHotkey, object: nil) }
            }
        }
    }

    private var axHint: String {
        if let t = askedAX, Date.now.timeIntervalSince(t) > 8, !ax {
            return "Still not on? If \(Brand.name) is already listed in the Accessibility pane, flip it off and on, or remove it with − and allow again. A relaunch fixes the rest."
        }
        return "Needed to notice the key you hold and to paste the text into the app you're using. \(Brand.name) never reads what's on your screen."
    }

    private var micAction: (String, () -> Void) {
        if mic == .denied { return ("Open Settings", { Permissions.openMicPane() }) }
        return ("Allow microphone", { Task { await Permissions.requestMic(); mic = Permissions.mic } })
    }

    private var retryAction: (String, () -> Void)? {
        guard state.warmError != nil else { return nil }
        return ("Retry", { NotificationCenter.default.post(name: .typevoiceRetryWarm, object: nil) })
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.glass)
            }
            Spacer()
            if step == 4 {
                Button(tried || revisiting ? "Done" : "Skip") {
                    NotificationCenter.default.post(name: .typevoiceOnboardingDone, object: nil)
                }
                .buttonStyle(tried ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
                .keyboardShortcut(tried ? .defaultAction : .cancelAction)
            } else {
                Button("Continue") { step += 1 }
                    .buttonStyle(.glassProminent)
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: trigger) { _, _ in NotificationCenter.default.post(name: .typevoiceTriggerChanged, object: nil) }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return mic == .granted
        case 1: return ax
        case 3: return state.isReady
        default: return true
        }
    }

    private func startPolling() {
        poll?.cancel()
        poll = Task { @MainActor in
            while !Task.isCancelled {
                let m = Permissions.mic, a = Permissions.accessibility
                if m != mic { mic = m }
                if a != ax { ax = a }
                if let t = askedAX, !a, Date.now.timeIntervalSince(t) > 8 { askedAX = t }
                if step == 0, m == .granted { try? await Task.sleep(for: .milliseconds(450)); step = 1 }
                else if step == 1, a { try? await Task.sleep(for: .milliseconds(450)); step = 2 }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }
}

private struct StepBar: View {
    let titles: [String]
    let current: Int
    let done: [Bool]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(titles.indices, id: \.self) { i in
                let complete = i < current && done[i]
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(i == current ? Color.accentColor : (complete ? Color.green : Color.secondary.opacity(0.18)))
                            .frame(width: 18, height: 18)
                        if complete {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(i == current ? .white : .secondary)
                        }
                    }
                    Text(titles[i])
                        .font(.system(size: 12, weight: i == current ? .semibold : .regular))
                        .foregroundStyle(i == current ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if i < titles.count - 1 {
                    Rectangle().fill(.separator).frame(height: 1).frame(minWidth: 10, maxWidth: .infinity)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
    }
}

private struct StepCard<Extra: View>: View {
    let icon: String
    let title: String
    let text: String
    var done: Bool
    var progress: WarmProgress? = nil
    var action: (String, () -> Void)? = nil
    var secondary: (String, () -> Void)? = nil
    @ViewBuilder var extra: Extra

    init(icon: String, title: String, text: String, done: Bool, progress: WarmProgress? = nil,
         action: (String, () -> Void)? = nil, secondary: (String, () -> Void)? = nil,
         @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.icon = icon; self.title = title; self.text = text; self.done = done
        self.progress = progress; self.action = action; self.secondary = secondary; self.extra = extra()
    }

    var body: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(done ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.14)).frame(width: 40, height: 40)
                        Image(systemName: done ? "checkmark" : icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(done ? Color.green : Color.accentColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                extra
                if let progress {
                    ModelProgressView(progress: progress)
                }
                if !done, action != nil || secondary != nil {
                    HStack(spacing: 10) {
                        if let action { Button(action.0, action: action.1).buttonStyle(.glassProminent) }
                        if let secondary { Button(secondary.0, action: secondary.1).buttonStyle(.glass) }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

/// The download step, shown properly: which stage, how far, and what it is.
struct ModelProgressView: View {
    let progress: WarmProgress
    private static let sizeMB = 450.0
    private var stages: [(WarmProgress.Phase, String)] { [(.downloading, "Download"), (.compiling, "Tune"), (.loading, "Load")] }
    private var stageIndex: Int {
        switch progress.phase { case .checking, .downloading: 0; case .compiling: 1; case .loading, .ready: 2 }
    }
    /// Whole-journey fraction: the download is the long part, tuning the rest.
    private var overall: Double {
        switch progress.phase {
        case .checking: 0
        case .downloading: progress.fraction * 0.7
        case .compiling: 0.7 + progress.fraction * 0.25
        case .loading: 0.95 + progress.fraction * 0.05
        case .ready: 1
        }
    }
    private var detail: String {
        switch progress.phase {
        case .checking: return "Checking what's already here…"
        case .downloading: return "\(Int(progress.fraction * Self.sizeMB)) of about \(Int(Self.sizeMB)) MB"
        case .compiling: return "Optimising for the Neural Engine, once…"
        case .loading: return "Almost there…"
        case .ready: return "Ready"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                    Text(stage.1)
                        .font(.system(size: 12, weight: i == stageIndex ? .semibold : .medium))
                        .foregroundStyle(i < stageIndex ? Color.green : i == stageIndex ? Color.primary : Color.secondary.opacity(0.7))
                    if i < stages.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary).padding(.horizontal, 8)
                    }
                }
                Spacer()
                Text("\(Int(overall * 100))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    Capsule().fill(Color.accentColor).frame(width: max(6, g.size.width * overall))
                        .animation(.easeOut(duration: 0.35), value: overall)
                }
            }
            .frame(height: 6)
            HStack {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().contentTransition(.numericText())
                Spacer()
                Text("NVIDIA Parakeet · runs on the Neural Engine").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }
}

/// Type-erased primitive button style so a Button can switch between glass styles.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

extension Notification.Name {
    static let typevoiceRetryWarm = Notification.Name("typevoice.retryWarm")
    static let typevoiceArmHotkey = Notification.Name("typevoice.armHotkey")
}
