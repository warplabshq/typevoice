import SwiftUI

/// Mirrored bars from the level history. Newest on the right.
struct WaveformView: View {
    let levels: [Float]
    var bars = 18
    var barWidth: CGFloat = 2
    var gap: CGFloat = 2.5
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            let slice = Array(levels.suffix(bars))
            let totalW = CGFloat(slice.count) * (barWidth + gap) - gap
            var x = (size.width - totalW) / 2
            let midY = size.height / 2
            let maxH = size.height
            for (i, l) in slice.enumerated() {
                let weight = 0.55 + 0.45 * CGFloat(i) / CGFloat(max(slice.count - 1, 1))
                let h = max(2, CGFloat(l) * maxH * weight)
                let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                let alpha = 0.45 + 0.55 * Double(weight)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color.opacity(alpha)))
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
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.onGlassDim)
                } else {
                    Circle()
                        .fill(Theme.accent.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .scaleEffect(s)
                }
            }
            .frame(width: 12, height: 12)
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
