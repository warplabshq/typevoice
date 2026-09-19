import AppKit
import SwiftUI

/// The one waveform. Eight bars, these heights, rounded ends, and fixed proportions taken
/// from the app icon: the gap is 0.82 of a bar's width and the tallest bar is 8.35 bar
/// widths high. Give any drawing a bar width and the rest follows, so the menu bar glyph,
/// the sidebar tile, the Summary card, the site's favicon and the resting shape of every
/// live waveform are the same object at different sizes. Change it here and re-run
/// `make icon`; nothing else hard-codes a bar.
enum BrandWave {
    static let heights: [CGFloat] = [0.16, 0.30, 0.52, 0.74, 0.46, 0.62, 0.34, 0.20]
    /// Gap as a fraction of the bar width (icon: 0.045 / 0.055).
    static let gapRatio: CGFloat = 0.82
    /// Tallest bar as a multiple of the bar width (icon: 0.74 × 0.62 / 0.055).
    static let tallest: CGFloat = 8.35

    /// Bar heights in points for a given bar width.
    static func barHeights(barWidth bw: CGFloat, heights: [CGFloat] = heights) -> [CGFloat] {
        heights.map { max(bw, $0 / 0.74 * tallest * bw) }
    }
    static func width(barWidth bw: CGFloat, bars: Int = heights.count) -> CGFloat {
        CGFloat(bars) * bw + CGFloat(bars - 1) * bw * gapRatio
    }

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
    /// `height` is the canvas; the bars are sized by `barWidth` alone and centred in it.
    static func image(height h: CGFloat, barWidth bw: CGFloat, alpha: CGFloat = 1, heights: [CGFloat] = heights) -> NSImage {
        let gap = bw * gapRatio
        let w = width(barWidth: bw)
        let bars = barHeights(barWidth: bw, heights: heights)
        let img = NSImage(size: NSSize(width: ceil(w), height: h), flipped: false) { rect in
            NSColor.black.withAlphaComponent(alpha).setFill()
            var x = (rect.width - w) / 2
            for bh in bars {
                // Snap to half points so bars stay crisp at 2x.
                let hh = min(h, (bh * 2).rounded() / 2)
                let r = NSRect(x: x, y: ((h - hh) / 2 * 2).rounded() / 2, width: bw, height: hh)
                NSBezierPath(roundedRect: r, xRadius: bw / 2, yRadius: bw / 2).fill()
                x += bw + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// The glyph as a SwiftUI view, in the current foreground colour. Size it by bar width.
struct BrandGlyph: View {
    var barWidth: CGFloat = 1.6
    var body: some View {
        let bars = BrandWave.barHeights(barWidth: barWidth)
        HStack(alignment: .center, spacing: barWidth * BrandWave.gapRatio) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, h in
                Capsule(style: .continuous).frame(width: barWidth, height: h)
            }
        }
        .frame(height: bars.max() ?? barWidth)
        .accessibilityHidden(true)
    }
}
