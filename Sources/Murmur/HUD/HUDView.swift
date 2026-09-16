import SwiftUI

/// The pill. Liquid Glass capsule whose width and contents follow `state.phase`.
struct HUDView: View {
    let state: AppState

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
            content
                .frame(height: 22)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(Color.black.opacity(0.45)), in: .capsule)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.6
                    )
                )
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
        }
        .scaleEffect(shown ? 1 : 0.9, anchor: UnitPoint(x: [0.0, 0.5, 1.0][position.horizontal], y: position.isTop ? 0 : 1))
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
                    WaveformView(levels: state.levels)
                        .frame(width: 80, height: 16)
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

        case .processing:
            ShimmerLine()
                .frame(width: 80)
                .transition(.blurFade)
                .id("processing")

        case .done(let text):
            TypeOnText(text: text, maxWidth: 440)
                .transition(.blurFade)
                .id("done-\(text.hashValue)")

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
