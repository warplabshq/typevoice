import AppKit
import SwiftUI

/// The one waveform. Eight bars, these heights, rounded ends, bars a little wider than the
/// gaps between them: the app icon, the menu bar glyph, the sidebar tile, the site's
/// favicon and the resting shape of every live waveform all draw this. Change it here
/// and re-run `make icon`; nothing else hard-codes a bar.
enum BrandWave {
    static let heights: [CGFloat] = [0.16, 0.30, 0.52, 0.74, 0.46, 0.62, 0.34, 0.20]
    /// Gap as a fraction of the bar width, from the icon (0.045 / 0.055).
    static let gapRatio: CGFloat = 0.82

    /// The same silhouette spread over any number of bars, for the live waveforms at rest.
    static func silhouette(bars: Int) -> [CGFloat] {
        guard bars > 0 else { return [] }
        if bars == heights.count { return heights }
        return (0..<bars).map { i in
            let pos = CGFloat(i) / CGFloat(max(bars - 1, 1)) * CGFloat(heights.count - 1)
            let lo = Int(pos.rounded(.down)), hi = min(lo + 1, heights.count - 1)
            let f = pos - CGFloat(lo)
            return heights[lo] * (1 - f) + heights[hi] * f
        }
    }

    /// A template NSImage of the glyph, for the menu bar and anywhere AppKit wants a picture.
    static func image(height h: CGFloat, barWidth bw: CGFloat, alpha: CGFloat = 1, heights: [CGFloat] = heights) -> NSImage {
        let gap = (bw * gapRatio * 4).rounded() / 4
        let w = CGFloat(heights.count) * bw + CGFloat(heights.count - 1) * gap
        let img = NSImage(size: NSSize(width: ceil(w), height: h), flipped: false) { rect in
            NSColor.black.withAlphaComponent(alpha).setFill()
            var x = (rect.width - w) / 2
            for f in heights {
                // Snap to half points so bars stay crisp at 2x.
                let bh = (f * h * 0.86 * 2).rounded() / 2
                let r = NSRect(x: x, y: ((h - bh) / 2 * 2).rounded() / 2, width: bw, height: bh)
                NSBezierPath(roundedRect: r, xRadius: bw / 2, yRadius: bw / 2).fill()
                x += bw + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The glyph as a SwiftUI view, in the current foreground colour.
struct BrandGlyph: View {
    var height: CGFloat = 14
    var barWidth: CGFloat = 1.6
    var body: some View {
        let gap = barWidth * BrandWave.gapRatio
        HStack(alignment: .center, spacing: gap) {
            ForEach(Array(BrandWave.heights.enumerated()), id: \.offset) { _, f in
                Capsule(style: .continuous)
                    .frame(width: barWidth, height: max(barWidth, f * height * 0.86))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
