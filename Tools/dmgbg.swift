// Renders the disk-image background at 1× and 2×: the site's light field, a soft lift under
// each icon, a hairline arrow, one caption. Nothing else: the icons are the message. Icon centres
// must match Packaging/dmg.py.  swift Tools/dmgbg.swift Packaging/dmg-background
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Packaging/dmg-background"
let W: CGFloat = 660, H: CGFloat = 480                      // taller than any Finder layout shows
let appX: CGFloat = 170, folderX: CGFloat = 490, iconY: CGFloat = 165

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)                   // the rep now maps points → pixels itself
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)      // y grows downwards, like the numbers above

    let field = CGColor(srgbRed: 0.957, green: 0.957, blue: 0.965, alpha: 1)   // #f4f4f6
    cg.setFillColor(field); cg.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // A soft white lift under each icon, so they sit on the field instead of floating.
    let space = CGColorSpaceCreateDeviceRGB()
    for x in [appX, folderX] {
        let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
        cg.drawRadialGradient(g, startCenter: CGPoint(x: x, y: iconY + 6), startRadius: 0,
                              endCenter: CGPoint(x: x, y: iconY + 6), endRadius: 130, options: [])
    }

    // Arrow: a hairline with an open head, midway between the icons.
    let y = iconY, x0 = appX + 96, x1 = folderX - 96
    cg.setStrokeColor(CGColor(gray: 0, alpha: 0.38)); cg.setLineWidth(1.8); cg.setLineCap(.round); cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: x0, y: y)); cg.addLine(to: CGPoint(x: x1, y: y))
    cg.move(to: CGPoint(x: x1 - 10, y: y - 9)); cg.addLine(to: CGPoint(x: x1, y: y)); cg.addLine(to: CGPoint(x: x1 - 10, y: y + 9))
    cg.strokePath()

    // Caption, through CoreText so it follows the flipped transform.
    let caption = NSAttributedString(string: "Drag TypeVoice into Applications, then open it from there.", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor(white: 0, alpha: 0.48)])
    let line = CTLineCreateWithAttributedString(caption)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    cg.textPosition = CGPoint(x: (W - bounds.width) / 2, y: 312)
    CTLineDraw(line, cg)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: URL(fileURLWithPath: out + ".png"))
try render(scale: 2).write(to: URL(fileURLWithPath: out + "@2x.png"))
print("wrote \(out).png and @2x")
