import SwiftUI

/// The pill. Liquid Glass capsule whose width and contents follow `state.phase`.
struct HUDView: View {
    let state: AppState
    var onCopy: () -> Void = {}
    var onDismiss: () -> Void = {}
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
            .animation(phase == .idle ? Theme.springSoft : Theme.spring, value: phase)
    }

    private var pill: some View {
        content.pillChrome()
        // Enters from its edge and retreats into it: slide + fade + slight shrink.
        .scaleEffect(shown ? 1 : 0.92,
                     anchor: UnitPoint(x: [0.0, 0.5, 1.0][position.horizontal], y: position.isTop ? 0 : 1))
        .offset(y: shown ? 0 : (position.isTop ? -HUDWindow.margin - 14 : HUDWindow.margin + 14))
        .opacity(shown ? 1 : 0)
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
                    Text(Prefs.triggerMode == .toggle ? "tap \(Prefs.triggerLabel) to stop" : "\(Prefs.triggerLabel) or esc to stop")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
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
            HStack(spacing: 12) {
                if !text.isEmpty {
                    TypeOnText(text: text, maxWidth: 400)
                    // If the paste didn't land (no text field under the cursor), the words are one click away.
                    CopyGlyphButton(action: onCopy)
                }
                if let url = state.lastAudio {
                    AudioChip(url: url, name: state.lastAudioName)
                }
                if !text.isEmpty || state.lastAudio != nil {
                    DismissButton(action: onDismiss)
                }
            }
            .transition(.blurFade)
            .id("done-\(text.hashValue)")

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

/// Drag this into any chat to send the voice instead of the words.
/// A small copy glyph beside the shown text; flips to a check for a moment when used.
struct CopyGlyphButton: View {
    let action: () -> Void
    @State private var hover = false
    @State private var copied = false
    var body: some View {
        Button {
            action()
            withAnimation(Theme.quick) { copied = true }
            Task { try? await Task.sleep(for: .milliseconds(1200)); withAnimation(Theme.quick) { copied = false } }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(hover || copied ? Color.black : Theme.onGlassDim)
                .frame(width: 22, height: 22)
                .background(hover || copied ? Color.white : Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Copy the text")
    }
}

/// The small × next to the audio chip: puts the pill away right now.
struct DismissButton: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hover ? Color.black : Theme.onGlassDim)
                .frame(width: 22, height: 22)
                .background(hover ? Color.white : Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Put the pill away")
    }
}

struct AudioChip: View {
    let url: URL
    let name: String
    @State private var hover = false
    var body: some View {
        RecordingDrag(url: url, fileName: name, onHover: { h in hover = h }) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Drag audio")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(hover ? Color.black : Theme.onGlass)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(hover ? Color.white : Color.white.opacity(0.14), in: Capsule())
        }
        .fixedSize()
        .help("Drag into a message to send the recording")
    }
}
