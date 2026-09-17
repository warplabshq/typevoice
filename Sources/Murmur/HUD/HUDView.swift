import SwiftUI

/// The pill. Liquid Glass capsule whose width and contents follow `state.phase`.
struct HUDView: View {
    let state: AppState
    var onCopy: () -> Void = {}
    @State private var hovering = false

    private var phase: AppState.Phase { state.phase }
    private var shown: Bool { phase.isActive }

    private var position: Prefs.HUDPosition { Prefs.hudPosition }

    private var alignment: Alignment {
        switch (position.isTop, position.horizontal) {
        case (true, 0): return .topLeading
        case (true, 1): return .top
        case (true, _): return .topTrailing
        case (false, 0): return .bottomLeading
        case (false, 1): return .bottom
        case (false, _): return .bottomTrailing
        }
    }

    var body: some View {
        pill
            .padding(HUDWindow.margin)
            .frame(width: HUDWindow.canvas.width, height: HUDWindow.canvas.height, alignment: alignment)
            .animation(Theme.spring, value: phase)
    }

    private var pill: some View {
        GlassEffectContainer(spacing: 0) {
            content.pillChrome()
        }
        .scaleEffect(shown ? (hovering && phase.isListening ? 1.03 : 1) : 0.9,
                     anchor: UnitPoint(x: [0.0, 0.5, 1.0][position.horizontal], y: position.isTop ? 0 : 1))
        .opacity(shown ? 1 : 0)
        .blur(radius: shown ? 0 : 5)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .listening(let locked):
            HStack(spacing: 10) {
                if locked { ListeningDot(locked: true) }
                if state.isReady {
                    WaveformView(bands: state.bands, bars: hovering ? 32 : 18, barWidth: 2.5, gap: 2, excited: hovering)
                        .frame(width: hovering ? 150 : 84, height: hovering ? 24 : 20)
                    if hovering, let since = state.listeningSince {
                        ElapsedLabel(since: since)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressRing(fraction: state.warm.fraction)
                        Text(state.warm.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.onGlassDim)
                    }
                }
                if locked {
                    Text("esc to stop")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.onGlassDim)
                }
            }
            .transition(.blurFade)
            .id("listening")
            .onHover { h in withAnimation(Theme.spring) { hovering = h } }

        case .processing:
            ShimmerLine()
                .frame(width: 80)
                .transition(.blurFade)
                .id("processing")

        case .done(let text):
            if text.isEmpty {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 80)
                    .transition(.blurFade)
                    .id("done-check")
            } else {
                TypeOnText(text: text, maxWidth: 440)
                    .transition(.blurFade)
                    .id("done-\(text.hashValue)")
            }

        case .copyOffer(let text, let copied):
            HStack(spacing: 12) {
                HuggingText(text: text, maxWidth: 360)
                Button(action: onCopy) {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(copied ? Theme.onGlassDim : .black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(copied ? Color.white.opacity(0.14) : Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: .command)
            }
            .transition(.blurFade)
            .id("copy")

        case .notHeard:
            message("Didn't catch that", icon: "waveform.slash")
                .id("notheard")

        case .error(let msg):
            message(msg, icon: "exclamationmark.circle")
                .id("error")
        }
    }

    private func message(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
            HuggingText(text: text, maxWidth: 420)
        }
        .transition(.blurFade)
    }
}

/// mm:ss that ticks while listening.
struct ElapsedLabel: View {
    let since: Date
    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            let s = max(0, Int(ctx.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", s / 60, s % 60))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.onGlassDim)
        }
    }
}
