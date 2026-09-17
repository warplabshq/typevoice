import AppKit
// Murmur icon: deep graphite squircle with a glossy top light, a fine rim, and
// luminous bars with a soft glow. Rendered at exact pixel sizes.
func render(_ size: Int, to url: URL) {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rgb = CGColorSpaceCreateDeviceRGB()
    let r = s * 0.2237
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let squircle = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    // Base: graphite with a cool tint, darker at the bottom.
    let base = CGGradient(colorsSpace: rgb, colors: [
        NSColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1).cgColor,
        NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor,
        NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1).cgColor] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    // Gloss: a bright sheen across the top third, fading out.
    let gloss = CGGradient(colorsSpace: rgb, colors: [
        NSColor(white: 1, alpha: 0.20).cgColor, NSColor(white: 1, alpha: 0.05).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
        locations: [0, 0.55, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: -s * 0.25, y: s * 0.55, width: s * 1.5, height: s * 0.95)); ctx.clip()
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s * 0.55), options: [])
    ctx.restoreGState()
    // Bottom warmth: faint glow rising from the bars.
    let under = CGGradient(colorsSpace: rgb, colors: [NSColor(white: 1, alpha: 0.10).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(under, startCenter: CGPoint(x: s * 0.5, y: s * 0.5), startRadius: 0, endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.55, options: [])
    ctx.restoreGState()

    // Rim: a hairline highlight along the top edge, shadow line at the bottom.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: s * 0.006, dy: s * 0.006), cornerWidth: r * 0.97, cornerHeight: r * 0.97, transform: nil))
    ctx.setLineWidth(s * 0.012)
    let rim = CGGradient(colorsSpace: rgb, colors: [NSColor(white: 1, alpha: 0.45).cgColor, NSColor(white: 1, alpha: 0.04).cgColor, NSColor(white: 0, alpha: 0.35).cgColor] as CFArray, locations: [0, 0.5, 1])!
    ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Bars with a soft glow behind them.
    let heights: [CGFloat] = [0.16, 0.30, 0.52, 0.74, 0.46, 0.62, 0.34, 0.20]
    let n = heights.count
    let bw = s * 0.055, gap = s * 0.045
    let total = CGFloat(n) * bw + CGFloat(n - 1) * gap
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let glow = CGGradient(colorsSpace: rgb, colors: [NSColor(white: 1, alpha: 0.28).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s * 0.5, y: s * 0.5), startRadius: 0, endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.42, options: [])
    var x = (s - total) / 2
    for h in heights {
        let bh = h * s * 0.62
        let br = CGRect(x: x, y: (s - bh) / 2, width: bw, height: bh)
        // drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor(white: 0, alpha: 0.55).cgColor)
        ctx.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: br, cornerWidth: bw / 2, cornerHeight: bw / 2, transform: nil)); ctx.fillPath()
        ctx.restoreGState()
        // vertical sheen on each bar
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: br, cornerWidth: bw / 2, cornerHeight: bw / 2, transform: nil)); ctx.clip()
        let sheen = CGGradient(colorsSpace: rgb, colors: [NSColor(white: 1, alpha: 1).cgColor, NSColor(white: 0.88, alpha: 1).cgColor, NSColor(white: 0.96, alpha: 1).cgColor] as CFArray, locations: [0, 0.6, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: br.maxY), end: CGPoint(x: 0, y: br.minY), options: [])
        ctx.restoreGState()
        x += bw + gap
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
for sz in [16, 32, 64, 128, 256, 512, 1024] { render(sz, to: out.appendingPathComponent("icon_\(sz).png")) }
print("icons written")
