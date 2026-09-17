import SwiftUI

/// Voice-reactive bars. Band energies (low → high) are laid out symmetrically
/// from the centre, interpolated to any bar count, eased per frame at 60 fps,
/// with peak caps and a soft glow that follows the overall energy.
struct WaveformView: View {
    /// Band energies 0…1, low → high.
    let bands: [Float]
    var bars = 18
    var barWidth: CGFloat = 2
    var gap: CGFloat = 2.5
    var color: Color = Theme.accent
    var excited = false          // hover: bigger swing, brighter glow

    @State private var display: [CGFloat] = []
    @State private var peaks: [CGFloat] = []
    @State private var lastTick: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
            Canvas { g, size in
                let n = bars
                let targets = Self.targets(bands: bands, bars: n)
                var disp = display.count == n ? display : Array(repeating: CGFloat(0), count: n)
                var pk = peaks.count == n ? peaks : Array(repeating: CGFloat(0), count: n)
                let dt = min(0.05, max(0.004, ctx.date.timeIntervalSince(lastTick)))
                let t = ctx.date.timeIntervalSinceReferenceDate
                let energy = targets.reduce(0, +) / CGFloat(max(n, 1))

                // Ease: fast up, slower down; frame-rate independent.
                let up = 1 - pow(0.001, dt * 6), down = 1 - pow(0.001, dt * 2.2)
                for i in 0..<n {
                    let target = targets[i]
                    disp[i] += (target - disp[i]) * (target > disp[i] ? up : down)
                    pk[i] = max(disp[i], pk[i] - CGFloat(dt) * 0.9)
                }

                // Silence: a slow, tiny breath so it never looks dead.
                let breathing = energy < 0.02
                let totalW = CGFloat(n) * (barWidth + gap) - gap
                var x = (size.width - totalW) / 2
                let midY = size.height / 2
                let maxH = size.height * (excited ? 1.0 : 0.92)

                // Glow behind the bars.
                if energy > 0.03 {
                    let glowW = totalW * 1.2, glowH = size.height * 2.2
                    let rect = CGRect(x: size.width / 2 - glowW / 2, y: midY - glowH / 2, width: glowW, height: glowH)
                    g.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [color.opacity(Double(energy) * (excited ? 0.45 : 0.28)), .clear]),
                        center: CGPoint(x: size.width / 2, y: midY), startRadius: 0, endRadius: glowW / 2))
                }

                for i in 0..<n {
                    var v = disp[i]
                    if breathing { v = 0.06 + 0.04 * CGFloat(sin(t * 1.6 + Double(i) * 0.45)) }
                    let h = max(2, v * maxH)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                    let alpha = 0.5 + 0.5 * Double(min(1, v * 1.4))
                    g.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(alpha)))
                    // Peak cap, only while there is real signal.
                    if !breathing, pk[i] > v + 0.08 {
                        let ph = pk[i] * maxH
                        let cap = CGRect(x: x, y: midY - ph / 2 - 1, width: barWidth, height: 2)
                        g.fill(Path(roundedRect: cap, cornerRadius: 1), with: .color(color.opacity(0.6)))
                    }
                    x += barWidth + gap
                }

                // Persist eased state for the next frame (outside the render pass).
                DispatchQueue.main.async {
                    display = disp; peaks = pk; lastTick = ctx.date
                }
            }
        }
        .drawingGroup()
    }

    /// Symmetric layout: centre bars take the low bands, edges the high bands,
    /// with a little left/right asymmetry so it reads as alive rather than mirrored.
    static func targets(bands: [Float], bars: Int) -> [CGFloat] {
        guard !bands.isEmpty, bars > 0 else { return Array(repeating: 0, count: bars) }
        let half = CGFloat(bars - 1) / 2
        return (0..<bars).map { i in
            let d = abs(CGFloat(i) - half) / max(half, 1)            // 0 at centre … 1 at edge
            let pos = d * CGFloat(bands.count - 1)
            let lo = Int(pos.rounded(.down)), hi = min(lo + 1, bands.count - 1)
            let f = pos - CGFloat(lo)
            var v = CGFloat(bands[lo]) * (1 - f) + CGFloat(bands[hi]) * f
            // Alternate bars lean on the neighbouring band so the two halves differ slightly.
            if i % 2 == 1 { v = v * 0.85 + CGFloat(bands[min(hi + 1, bands.count - 1)]) * 0.15 }
            return min(1, v)
        }
    }
}

/// Lock glyph shown when hands-free.
struct ListeningDot: View {
    let locked: Bool
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.onGlassDim)
            .frame(width: 12, height: 12)
    }
}

/// A single hairline that shimmers while the model works.
struct ShimmerLine: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t * 0.9).truncatingRemainder(dividingBy: 1))
            GeometryReader { g in
                let w = g.size.width
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 2)
                    .overlay(
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, Theme.onGlass.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: w * 0.35, height: 2)
                            .offset(x: -w * 0.35 + (w + w * 0.35) * phase)
                    )
                    .clipShape(Capsule())
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// Ring used while the model downloads / compiles on first run.
struct ProgressRing: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var track: Color = Color.white.opacity(0.12)
    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .frame(width: 16, height: 16)
    }
}

/// Synthetic bands for previews: a voice-like pattern with syllable rhythm.
enum DemoBands {
    static func at(_ t: Double, bands: Int = 10) -> [Float] {
        let syllable = (0.35 + 0.65 * max(0, sin(t * 4.2))) * (0.7 + 0.3 * sin(t * 0.9))
        return (0..<bands).map { b in
            let d = Double(b)
            let formant = 0.55 + 0.45 * sin(t * 2.7 + d * 1.1)
            let tilt = 1 - d * 0.055
            return Float(min(1, max(0, (0.15 + 0.85 * syllable * formant) * tilt)))
        }
    }
}
