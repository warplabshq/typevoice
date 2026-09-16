import SwiftUI

/// The pill. Liquid Glass capsule whose width and contents follow `state.phase`.
struct HUDView: View {
    let state: AppState

    private var phase: AppState.Phase { state.phase }
    private var shown: Bool { phase.isActive }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if Prefs.hudPosition == .top { pill; Spacer(minLength: 0) } else { pill }
        }
        .frame(width: HUDWindow.canvas.width, height: HUDWindow.canvas.height)
        .animation(Theme.spring, value: phase)
    }

    private var pill: some View {
        GlassEffectContainer(spacing: 0) {
            content
                .frame(height: 30)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular.tint(Color.black.opacity(0.42)), in: .capsule)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                )
                .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        }
        .padding(.bottom, 8)
        .scaleEffect(shown ? 1 : 0.86, anchor: Prefs.hudPosition == .top ? .top : .bottom)
        .opacity(shown ? 1 : 0)
        .blur(radius: shown ? 0 : 6)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            EmptyView()

        case .listening(let locked):
            HStack(spacing: 12) {
                ListeningDot(locked: locked)
                if state.isReady {
                    WaveformView(levels: state.levels)
                        .frame(width: 150)
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
                .frame(width: 150)
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
