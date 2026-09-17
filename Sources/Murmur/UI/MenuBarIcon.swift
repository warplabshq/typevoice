import AppKit

/// The menu bar glyph: the same eight bars as the app icon, as a template image so it
/// follows the menu bar's light and dark appearance.
enum MenuBarIcon {
    /// Bar heights from the app icon, relative to the glyph height.
    static let heights: [CGFloat] = [0.16, 0.30, 0.52, 0.74, 0.46, 0.62, 0.34, 0.20]

    static let image: NSImage = {
        let h: CGFloat = 16, bw: CGFloat = 1.5, gap: CGFloat = 1.0
        let w = CGFloat(heights.count) * bw + CGFloat(heights.count - 1) * gap
        let img = NSImage(size: NSSize(width: ceil(w), height: h), flipped: false) { rect in
            NSColor.black.setFill()
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
    }()
}
