import AppKit
import CoreText
// Brand assets for stores, checkout pages and press: icon PNGs, the wordmark and the lockup
// (icon + name) on dark, on light and on transparent, plus a square product tile.
// usage: swift Tools/brand.swift <iconset dir with icon_1024.png> <font dir> <out dir>
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
let fontDir = URL(fileURLWithPath: CommandLine.arguments[2])
let out = URL(fileURLWithPath: CommandLine.arguments[3])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for f in ["InstrumentSerif-Regular.ttf", "InstrumentSerif-Italic.ttf"] {
    CTFontManagerRegisterFontsForURL(fontDir.appendingPathComponent(f) as CFURL, .process, nil)
}
let icon = NSImage(contentsOf: iconset.appendingPathComponent("icon_1024.png"))!

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("  \(name)  \(rep.pixelsWide)×\(rep.pixelsHigh)")
}
let dark = NSColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)
let light = NSColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)

/// Wordmark: "TypeVoice" in the serif with the site's tight tracking.
func wordmark(size: CGFloat, color: NSColor) -> NSAttributedString {
    let f = NSFont(name: "Instrument Serif", size: size)!
    return NSAttributedString(string: "TypeVoice", attributes: [.font: f, .foregroundColor: color, .kern: -size * 0.02])
}

// 1. Icon sizes as plain PNGs (the 1024 is what stores and Dodo want for a product image).
for s in [1024, 512, 256, 128] {
    let rep = canvas(s, s) { _ in icon.draw(in: NSRect(x: 0, y: 0, width: s, height: s)) }
    save(rep, "icon-\(s).png")
}

// 2. Lockups: icon + wordmark, on dark, on light, and transparent (dark text / light text).
for (name, bg, fg) in [("lockup-dark", dark, NSColor.white), ("lockup-light", light, NSColor(white: 0.07, alpha: 1)),
                       ("lockup-transparent-for-dark", NSColor.clear, NSColor.white), ("lockup-transparent-for-light", NSColor.clear, NSColor(white: 0.07, alpha: 1))] {
    let W = 2400, H = 800
    let rep = canvas(W, H) { ctx in
        if bg != .clear { ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        let iconSize: CGFloat = 400
        let word = wordmark(size: 300, color: fg)
        let wordW = word.size().width
        let total = iconSize + 88 + wordW
        let x0 = (CGFloat(W) - total) / 2
        icon.draw(in: NSRect(x: x0, y: (CGFloat(H) - iconSize) / 2, width: iconSize, height: iconSize))
        // Optical centre of the serif sits a touch above its baseline box.
        word.draw(at: NSPoint(x: x0 + iconSize + 88, y: (CGFloat(H) - word.size().height) / 2 + 18))
    }
    save(rep, "\(name).png")
}

// 3. Wordmark alone, transparent.
for (name, fg) in [("wordmark-white", NSColor.white), ("wordmark-black", NSColor(white: 0.07, alpha: 1))] {
    let word = wordmark(size: 400, color: fg)
    let W = Int(word.size().width) + 80, H = 520
    let rep = canvas(W, H) { _ in word.draw(at: NSPoint(x: 40, y: (CGFloat(H) - word.size().height) / 2 + 20)) }
    save(rep, "\(name).png")
}

// 4. Square product tile (1200×1200): icon on the dark field with the name beneath — checkout
//    pages and store listings crop to a square.
do {
    let S = 1200
    let rep = canvas(S, S) { ctx in
        ctx.setFillColor(dark.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0.47, green: 0.55, blue: 0.82, alpha: 0.14).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 600, y: 760), startRadius: 0, endCenter: CGPoint(x: 600, y: 760), endRadius: 700, options: [])
        icon.draw(in: NSRect(x: (1200 - 560) / 2, y: 430, width: 560, height: 560))
        let word = wordmark(size: 150, color: .white)
        word.draw(at: NSPoint(x: (1200 - word.size().width) / 2, y: 250))
        let sub = NSAttributedString(string: "Local dictation for Mac", attributes: [.font: NSFont.systemFont(ofSize: 44, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.58)])
        sub.draw(at: NSPoint(x: (1200 - sub.size().width) / 2, y: 180))
    }
    save(rep, "product-tile-1200.png")
}

// 5. Wide banner (2400×1000) for storefronts that want a hero: headline + pill, like the OG image.
do {
    let W = 2400, H = 1000
    let rep = canvas(W, H) { ctx in
        ctx.setFillColor(dark.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(red: 0.47, green: 0.55, blue: 0.82, alpha: 0.16).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 1200, y: 1020), startRadius: 0, endCenter: CGPoint(x: 1200, y: 1020), endRadius: 1200, options: [])
        icon.draw(in: NSRect(x: 160, y: 1000 - 160 - 180, width: 180, height: 180))
        let tag = NSAttributedString(string: "LOCAL DICTATION FOR MAC", attributes: [.font: NSFont.systemFont(ofSize: 38, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.55), .kern: 4.5])
        tag.draw(at: NSPoint(x: 160, y: 1000 - 160 - 180 - 80))
        let serif = NSFont(name: "Instrument Serif", size: 236)!, serifI = NSFont(name: "Instrument Serif Italic", size: 236)!
        NSAttributedString(string: "Just talk.", attributes: [.font: serif, .foregroundColor: NSColor.white, .kern: -4]).draw(at: NSPoint(x: 150, y: 330))
        NSAttributedString(string: "It's typed.", attributes: [.font: serifI, .foregroundColor: NSColor.white, .kern: -4]).draw(at: NSPoint(x: 150, y: 100))
        let pill = CGRect(x: 1520, y: 400, width: 720, height: 208)
        ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -28), blur: 80, color: NSColor(white: 0, alpha: 0.6).cgColor)
        ctx.setFillColor(NSColor.black.cgColor); ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 104, cornerHeight: 104, transform: nil)); ctx.fillPath(); ctx.restoreGState()
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.09).cgColor); ctx.setLineWidth(3); ctx.addPath(CGPath(roundedRect: pill.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 104, cornerHeight: 104, transform: nil)); ctx.strokePath()
        // The brand waveform, spread over the pill's 18 bars at rest (same numbers as BrandWave).
        let brand: [CGFloat] = [0.16, 0.30, 0.52, 0.74, 0.46, 0.62, 0.34, 0.20]
        let bars = 18
        let heights: [CGFloat] = (0..<bars).map { i in
            let pos = CGFloat(i) / CGFloat(bars - 1) * CGFloat(brand.count - 1)
            let lo = Int(pos.rounded(.down)), hi = min(lo + 1, brand.count - 1), f = pos - CGFloat(lo)
            return brand[lo] * (1 - f) + brand[hi] * f
        }
        let bw: CGFloat = 10, gap: CGFloat = 12, total = CGFloat(bars) * (bw + gap) - gap
        var x = pill.midX - total / 2
        for h in heights {
            let bh = max(bw, h * 150)
            ctx.setFillColor(NSColor(white: 1, alpha: 0.95).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: pill.midY - bh / 2, width: bw, height: bh), cornerWidth: bw / 2, cornerHeight: bw / 2, transform: nil)); ctx.fillPath()
            x += bw + gap
        }
    }
    save(rep, "banner-2400x1000.png")
}
print("done →", out.path)
