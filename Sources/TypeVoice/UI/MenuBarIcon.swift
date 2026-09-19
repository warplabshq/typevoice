import AppKit

/// The menu bar glyph: the same eight bars as the app icon, as a template image so it
/// follows the menu bar's light and dark appearance. Three states so the menu bar tells
/// you what the app is doing without a HUD: resting bars, bars raised while listening,
/// and a dimmed glyph while it works on the words.
enum MenuBarIcon {
    /// Bar heights from the app icon, relative to the glyph height.
    static let heights: [CGFloat] = [0.16, 0.30, 0.52, 0.74, 0.46, 0.62, 0.34, 0.20]
    /// Raised, as if mid-sentence.
    static let listeningHeights: [CGFloat] = [0.40, 0.66, 0.90, 0.98, 0.78, 0.94, 0.70, 0.44]

    static let image = render(heights, alpha: 1)
    static let listening = render(listeningHeights, alpha: 1)
    static let processing = render(heights, alpha: 0.42)
    static let paused = render(heights.map { $0 * 0.55 }, alpha: 0.55)

    static func image(for phase: AppState.Phase, paused: Bool) -> NSImage {
        if paused { return Self.paused }
        switch phase {
        case .listening: return listening
        case .processing: return processing
        default: return image
        }
    }

    private static func render(_ heights: [CGFloat], alpha: CGFloat) -> NSImage {
        let h: CGFloat = 16, bw: CGFloat = 1.5, gap: CGFloat = 1.0
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
