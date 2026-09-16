import SwiftUI

/// Mirrored bars from the level history. Newest on the right.
struct WaveformView: View {
    let levels: [Float]
    var bars = 26
    var barWidth: CGFloat = 3
    var gap: CGFloat = 3

    var body: some View {
        Canvas { ctx, size in
            let slice = Array(levels.suffix(bars))
            let totalW = CGFloat(slice.count) * (barWidth + gap) - gap
            var x = (size.width - totalW) / 2
            let midY = size.height / 2
            let maxH = size.height - 4
            for (i, l) in slice.enumerated() {
                // Emphasise the tail a little so motion reads left→right.
                let weight = 0.6 + 0.4 * CGFloat(i) / CGFloat(max(slice.count - 1, 1))
                let h = max(2.5, CGFloat(l) * maxH * weight)
                let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Theme.accentSoft, Theme.accent]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: shading)
                x += barWidth + gap
            }
        }
        .drawingGroup()
    }
}

/// Small breathing dot for "listening"; becomes a lock when hands-free.
struct ListeningDot: View {
    let locked: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = 1 + 0.18 * sin(t * 3.2)
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(locked ? 1 : s * 1.15)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                        .scaleEffect(s)
                }
            }
            .frame(width: 18, height: 18)
        }
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
                            .fill(LinearGradient(colors: [.clear, Theme.accentSoft, .clear], startPoint: .leading, endPoint: .trailing))
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
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .frame(width: 16, height: 16)
    }
}
