import AppKit
import SwiftUI

/// Four cards. Each one polls its permission and moves on by itself.
struct OnboardingView: View {
    let state: AppState
    @State private var step = 0
    @State private var mic = Permissions.mic
    @State private var ax = Permissions.accessibility
    @State private var poll: Task<Void, Never>?
    @State private var askedAX: Date?

    private let steps = ["Microphone", "Accessibility", "Globe key", "Model"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            card
                .id(step)
                .transition(.blurFade)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            footer
        }
        .padding(36)
        .frame(width: 520, height: 560)
        .background(
            LinearGradient(colors: [Color(white: 0.11), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
        .animation(Theme.springSoft, value: step)
        .onAppear(perform: startPolling)
        .onDisappear { poll?.cancel() }
    }

    private var header: some View {
        VStack(spacing: 14) {
            MiniPill()
            Text("Murmur")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.onGlass)
            Text("Hold a key. Talk. Release. It's typed.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.onGlassDim)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var card: some View {
        switch step {
        case 0:
            StepCard(
                icon: "mic.fill",
                title: "Microphone",
                text: "Murmur listens only while you hold the key. Audio never leaves this Mac.",
                done: mic == .granted,
                action: micAction
            )
        case 1:
            StepCard(
                icon: "hand.raised.fill",
                title: "Accessibility",
                text: axHint,
                done: ax,
                action: ("Allow accessibility", { askedAX = .now; Permissions.requestAccessibility(); Permissions.openAccessibilityPane() }),
                secondary: askedAX == nil ? nil : ("Relaunch Murmur", { Permissions.relaunch() })
            )
        case 2:
            StepCard(
                icon: "globe",
                title: "Free the Globe key",
                text: "In System Settings › Keyboard, set “Press 🌐 key to” to Do Nothing. Otherwise macOS opens the emoji picker every time you hold it.",
                done: false,
                action: ("Open Keyboard settings", { Permissions.openKeyboardPane() }),
                secondary: ("I've done this", { step = 3 })
            )
        default:
            StepCard(
                icon: "cpu",
                title: "Speech model",
                text: state.warmError ?? (state.isReady ? "Ready. Everything runs on the Neural Engine." : "One-time download and optimisation for this Mac. About a minute."),
                done: state.isReady,
                progress: state.isReady ? nil : state.warm,
                action: retryAction
            )
        }
    }

    private var axHint: String {
        if let t = askedAX, Date.now.timeIntervalSince(t) > 8, !ax {
            return "Switched it on but still stuck? macOS sometimes only notices after a relaunch. If Murmur is already listed, flip it off and on again, then relaunch."
        }
        return "Needed to notice the 🌐 key and to type into the app you're using. Murmur never reads what's on your screen."
    }

    private var micAction: (String, () -> Void) {
        if mic == .denied {
            return ("Open Settings", { Permissions.openMicPane() })
        }
        return ("Allow microphone", { Task { await Permissions.requestMic(); mic = Permissions.mic } })
    }

    private var retryAction: (String, () -> Void)? {
        guard state.warmError != nil else { return nil }
        return ("Retry", { NotificationCenter.default.post(name: .murmurRetryWarm, object: nil) })
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Theme.accent : Color.white.opacity(0.15))
                        .frame(width: i == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if step == 3 {
                Button("Start dictating") {
                    NotificationCenter.default.post(name: .murmurOnboardingDone, object: nil)
                }
                .buttonStyle(.glassProminent)
                .disabled(!state.isReady)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { step += 1 }
                    .buttonStyle(.glassProminent)
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return mic == .granted
        case 1: return ax
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
                if let t = askedAX, !a, Date.now.timeIntervalSince(t) > 8 { askedAX = t }   // nudge re-render
                if step == 0, m == .granted { try? await Task.sleep(for: .milliseconds(500)); step = 1 }
                else if step == 1, a { try? await Task.sleep(for: .milliseconds(500)); step = 2 }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}

private struct StepCard: View {
    let icon: String
    let title: String
    let text: String
    var done: Bool
    var progress: WarmProgress? = nil
    var action: (String, () -> Void)? = nil
    var secondary: (String, () -> Void)? = nil


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08)).frame(width: 40, height: 40)
                    Image(systemName: done ? "checkmark" : icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(done ? Theme.accent : Theme.onGlass)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.onGlass)
                Spacer()
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.onGlassDim)
                .fixedSize(horizontal: false, vertical: true)
            if let progress {
                HStack(spacing: 10) {
                    ProgressRing(fraction: progress.fraction)
                    Text(progress.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.onGlassDim)
                }
                .padding(.top, 2)
            }
            if !done, action != nil || secondary != nil {
                HStack(spacing: 10) {
                    if let action {
                        Button(action.0, action: action.1).buttonStyle(.glassProminent)
                    }
                    if let secondary {
                        Button(secondary.0, action: secondary.1).buttonStyle(.glass)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(22)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

/// The pill, as the onboarding hero.
private struct MiniPill: View {
    static func levels(at time: Double) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(26)
        for i in 0..<26 {
            let d = Double(i)
            let fast: Double = abs(sin(time * 2.1 + d * 0.55))
            let slow: Double = 0.5 + 0.5 * sin(time * 0.7 + d * 0.2)
            let v: Double = 0.25 + 0.6 * fast * slow
            out.append(Float(v))
        }
        return out
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let levels = MiniPill.levels(at: ctx.date.timeIntervalSinceReferenceDate)
            HStack(spacing: 12) {
                ListeningDot(locked: false)
                WaveformView(levels: levels).frame(width: 150)
            }
            .frame(height: 30)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular.tint(Color.black.opacity(0.42)), in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        }
        .frame(height: 64)
    }
}

extension Notification.Name {
    static let murmurRetryWarm = Notification.Name("murmur.retryWarm")
}
