// Renders the DMG window background (640×440 points):
//   swift dmg-background.swift <out.png> <scale> "<caption>" <accent hex> <second accent hex>
// Light and quiet, so Finder's (black) icon labels stay readable; the two accents tint the glow and the arrow.
// Finder anchors the picture under the title bar and, if the user shows it, the tab bar (~40 pt): everything that
// matters sits in the top 340 pt, and the rest is plain background that may be cut off.
import AppKit
import CoreText

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let scale = CGFloat(Double(args.count > 2 ? args[2] : "1") ?? 1)
let caption = args.count > 3 ? args[3] : "Drag the app into Applications"
let accent = UInt32(args.count > 4 ? args[4] : "FF4757", radix: 16) ?? 0xFF4757
let accent2 = UInt32(args.count > 5 ? args[5] : "FFA24C", radix: 16) ?? 0xFFA24C
let W: CGFloat = 640, H: CGFloat = 440
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
// Work top-left origin, like Finder's icon positions.
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Base: near-white, a touch cooler at the bottom.
let base = CGGradient(colorsSpace: space, colors: [rgb(0xFCFCFD), rgb(0xF2F2F6)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: H), options: [])

// Soft pastel light: lavender above, the two accents low behind the arrow.
func glow(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}
glow(CGPoint(x: 320, y: -40), 330, rgb(0xDCDEF7, 0.75))
glow(CGPoint(x: 250, y: 300), 260, rgb(accent, 0.10))
glow(CGPoint(x: 420, y: 270), 240, rgb(accent2, 0.13))

// The arrow between the app (x 165) and Applications (x 475), on the icons' centre line (see dmg-settings.py).
let y: CGFloat = 165, x0: CGFloat = 262, x1: CGFloat = 378
ctx.saveGState()
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: x0, y: y)); arrow.addLine(to: CGPoint(x: x1, y: y))
arrow.move(to: CGPoint(x: x1 - 9, y: y - 8)); arrow.addLine(to: CGPoint(x: x1, y: y)); arrow.addLine(to: CGPoint(x: x1 - 9, y: y + 8))
ctx.addPath(arrow)
ctx.setLineWidth(2); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.replacePathWithStrokedPath(); ctx.clip()
let cut = CGGradient(colorsSpace: space, colors: [rgb(accent, 0.25), rgb(accent, 0.9), rgb(accent2)] as CFArray,
                     locations: [0, 0.45, 1])!
ctx.drawLinearGradient(cut, start: CGPoint(x: x0, y: y), end: CGPoint(x: x1, y: y), options: [])
ctx.restoreGState()

// Caption, centred under the icons and their labels.
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, y: CGFloat, tracking: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: tracking])
    let line = CTLineCreateWithAttributedString(str)
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // undo the flip for glyphs
    ctx.textPosition = CGPoint(x: (W - CGFloat(w)) / 2, y: y)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}
text(caption, size: 13, weight: .medium, color: rgb(0x5A5C66), y: 300, tracking: 0.1)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: W, height: H) // points, so the @2x render is marked 144 dpi
try! rep.representation(using: .png, properties: [:])!.write(to: out)
