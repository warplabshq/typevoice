import AppKit
import SwiftUI

/// Voice-reactive bars on Core Animation layers. Each bar is a CALayer; an
/// update is a handful of property sets and the render server interpolates
/// between them, so the main thread does almost nothing per frame.
struct WaveformView: NSViewRepresentable {
    /// Band energies 0…1, low → high. Ignored when `demo` is on.
    var bands: [Float] = []
    var bars = 18
    var barWidth: CGFloat = 2
    var gap: CGFloat = 2.5
    var color: Color = Theme.accent
    var excited = false
    /// Self-driven synthetic voice for previews.
    var demo = false

    func makeNSView(context: Context) -> BarsView {
        let v = BarsView()
        v.configure(bars: bars, barWidth: barWidth, gap: gap, color: NSColor(color), excited: excited)
        if demo { v.startDemo() } else { v.apply(bands: bands) }
        return v
    }

    func updateNSView(_ v: BarsView, context: Context) {
        v.configure(bars: bars, barWidth: barWidth, gap: gap, color: NSColor(color), excited: excited)
        if demo { v.startDemo() } else { v.apply(bands: bands) }
    }

    /// Centre bars take the low bands, edges the high bands; a 3-tap blur across
    /// neighbours makes the outline flow instead of flicker bar by bar.
    static func targets(bands: [Float], bars: Int) -> [CGFloat] {
        guard !bands.isEmpty, bars > 0 else { return Array(repeating: 0, count: bars) }
        let half = CGFloat(bars - 1) / 2
        var raw: [CGFloat] = (0..<bars).map { i in
            let d = abs(CGFloat(i) - half) / max(half, 1)
            let pos = d * CGFloat(bands.count - 1)
            let lo = Int(pos.rounded(.down)), hi = min(lo + 1, bands.count - 1)
            let f = pos - CGFloat(lo)
            var v = CGFloat(bands[lo]) * (1 - f) + CGFloat(bands[hi]) * f
            if i % 2 == 1 { v = v * 0.85 + CGFloat(bands[min(hi + 1, bands.count - 1)]) * 0.15 }
            return min(1, v)
        }
        if bars >= 3 {
            var out = raw
            for i in 1..<(bars - 1) { out[i] = raw[i - 1] * 0.25 + raw[i] * 0.5 + raw[i + 1] * 0.25 }
            raw = out
        }
        return raw
    }
}

final class BarsView: NSView {
    private var barLayers: [CALayer] = []
    private var bars = 18
    private var barWidth: CGFloat = 2
    private var gap: CGFloat = 2.5
    private var color = NSColor.white
    private var excited = false
    private var breathing = false
    private var demoTimer: Timer?
    private var demoStart = Date()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { demoTimer?.invalidate() }

    override var isFlipped: Bool { true }

    func configure(bars: Int, barWidth: CGFloat, gap: CGFloat, color: NSColor, excited: Bool) {
        let rebuild = bars != self.bars || barLayers.isEmpty
        self.bars = bars; self.barWidth = barWidth; self.gap = gap; self.excited = excited
        if !color.isEqual(self.color) || rebuild {
            self.color = color
            for (i, l) in barLayers.enumerated() { l.backgroundColor = colorFor(i).cgColor }
        }
        if rebuild {
            // A different bar count (hover grows 18 → 32): cross-fade the two sets rather
            // than swapping them, so the change reads as the wave spreading, not a cut.
            let old = barLayers
            barLayers = (0..<bars).map { i in
                let l = CALayer()
                l.backgroundColor = colorFor(i).cgColor
                l.cornerRadius = barWidth / 2
                l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                l.opacity = old.isEmpty ? 1 : 0
                layer?.addSublayer(l)
                return l
            }
            let startHeights = (0..<bars).map { i -> CGFloat in
                guard !old.isEmpty else { return 2 }
                let j = Int((CGFloat(i) / CGFloat(max(bars - 1, 1))) * CGFloat(old.count - 1))
                return old[j].bounds.height
            }
            layoutBars(heights: startHeights, animated: false)
            if !old.isEmpty {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.26)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                CATransaction.setCompletionBlock { old.forEach { $0.removeFromSuperlayer() } }
                barLayers.forEach { $0.opacity = 1 }
                old.forEach { $0.opacity = 0 }
                CATransaction.commit()
            }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutBars(heights: barLayers.map { $0.bounds.height }, animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        barLayers.forEach { $0.contentsScale = window?.backingScaleFactor ?? 2 }
        layoutBars(heights: barLayers.map { $0.bounds.height }, animated: false)
    }

    private func colorFor(_ i: Int) -> NSColor {
        let half = CGFloat(max(bars - 1, 1)) / 2
        let edge = abs(CGFloat(i) - half) / max(half, 1)
        return color.withAlphaComponent(0.95 - 0.3 * edge)
    }

    private func snap(_ v: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (v * scale).rounded() / scale
    }

    private func layoutBars(heights: [CGFloat], animated: Bool, rising: [Bool]? = nil) {
        guard barLayers.count == bars, heights.count == bars else { return }
        let bw = snap(barWidth), gp = snap(gap)
        let totalW = CGFloat(bars) * (bw + gp) - gp
        // While SwiftUI is still animating the frame (hover grows it), the bars would spill
        // past the capsule. Squeeze the spacing to what fits right now; it relaxes as the
        // frame catches up, so the wave and the capsule grow together.
        let fit = totalW > 0 ? min(1, bounds.width / totalW) : 1
        let step = (bw + gp) * fit
        var x = snap((bounds.width - (totalW * fit)) / 2)
        let midY = snap(bounds.height / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }
        for (i, l) in barLayers.enumerated() {
            let h = max(snap(2), snap(heights[i]))
            if animated {
                // Faster up, slower down: the classic meter feel.
                let up = rising?[i] ?? true
                CATransaction.setAnimationDuration(up ? 0.09 : 0.22)
            }
            l.bounds = CGRect(x: 0, y: 0, width: bw, height: h)
            l.position = CGPoint(x: x + bw / 2, y: midY)
            l.cornerRadius = bw / 2
            x += step
        }
        CATransaction.commit()
    }

    /// Feed real band energies (0…1, low → high).
    func apply(bands: [Float]) {
        stopDemo()
        let targets = WaveformView.targets(bands: bands, bars: bars)
        let energy = targets.reduce(0, +) / CGFloat(max(bars, 1))
        if energy < 0.02 { startBreathing(); return }
        stopBreathing()
        let maxH = bounds.height * (excited ? 0.9 : 0.82)
        let heights = targets.map { $0 * maxH }
        let rising = zip(heights, barLayers).map { $0 > $1.presentation()?.bounds.height ?? $1.bounds.height }
        layoutBars(heights: heights, animated: true, rising: rising)
    }

    // MARK: Idle breathing

    private func startBreathing() {
        guard !breathing else { return }
        breathing = true
        let base = max(2, bounds.height * 0.07)
        for (i, l) in barLayers.enumerated() {
            let a = CABasicAnimation(keyPath: "bounds.size.height")
            a.fromValue = base * 0.6
            a.toValue = base * 1.4
            a.duration = 1.6
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timeOffset = Double(i) * 0.09
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(a, forKey: "breathe")
        }
        layoutBars(heights: Array(repeating: base, count: bars), animated: true)
    }

    private func stopBreathing() {
        guard breathing else { return }
        breathing = false
        barLayers.forEach { $0.removeAnimation(forKey: "breathe") }
    }

    // MARK: Demo

    func startDemo() {
        guard demoTimer == nil else { return }
        demoStart = Date()
        let t = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self, let w = self.window, w.isVisible, !w.isMiniaturized else { return }
            let time = Date().timeIntervalSince(self.demoStart)
            let targets = WaveformView.targets(bands: DemoBands.at(time), bars: self.bars)
            let maxH = self.bounds.height * 0.82
            self.layoutBars(heights: targets.map { $0 * maxH }, animated: true)
        }
        RunLoop.main.add(t, forMode: .common)
        demoTimer = t
    }

    private func stopDemo() {
        demoTimer?.invalidate()
        demoTimer = nil
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
