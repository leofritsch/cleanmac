// Draws the Clean Mac icon as an Icon Composer document: a front-facing drive whose glass lid
// splits a glare into the strata hues. macOS derives the dark, clear and tinted looks from its layers.
// Usage: swift scripts/make-icon.swift <AppIcon.icon>
import AppKit
import CoreImage

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.icon")
let assets = out.appendingPathComponent("Assets")
try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}
func canvas() -> CGContext {
    CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ ctx: CGContext, _ name: String) {
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! png.write(to: assets.appendingPathComponent(name))
}
func blurred(_ image: CGImage, sigma: CGFloat) -> CGImage {
    let blur = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: frame)
    return CIContext().createCGImage(blur, from: frame)!
}

// Full-bleed 1024 canvas; macOS applies the rounded-rect mask and margins.
// The drive is seen from the front and a little above, so the lid is foreshortened by k.
let W: CGFloat = 422, D: CGFloat = 323, k: CGFloat = 0.42, r: CGFloat = 104, H: CGFloat = 236
let cx: CGFloat = 512, cy: CGFloat = 382
let lidTop = cy + H + D * k, lip = cy + H - D * k, floor = cy - D * k

func face(_ z: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: -W, y: -D, width: 2 * W, height: 2 * D), cornerWidth: r, cornerHeight: r,
           transform: [CGAffineTransform(a: 1, b: 0, c: 0, d: k, tx: cx, ty: cy + z)])
}
let lid = face(H)
let body: CGPath = {
    let p = CGMutablePath()
    var z: CGFloat = 0
    while z < H { p.addPath(face(z)); z += 0.5 }
    p.addPath(lid)
    return p
}()

// A white streak split into the strata hues: cool on one side, warm on the other
let prism = gradient([
    (color(0x4F74FF, 0), 0.10), (color(0x4F74FF), 0.24), (color(0xA27BFF), 0.31), (color(0x38C8F0), 0.37),
    (color(0xFFFFFF), 0.42), (color(0xFFFFFF), 0.45), (color(0x3FD68A), 0.50), (color(0xFFC23D), 0.56),
    (color(0xFF7A59), 0.63), (color(0xFF7A59, 0), 0.78),
])
let glare: CGImage = {
    let ctx = canvas()
    ctx.addPath(lid)
    ctx.clip()
    ctx.drawLinearGradient(prism, start: CGPoint(x: cx - W, y: lidTop + 174), end: CGPoint(x: cx + W, y: lip - 174), options: [])
    return ctx.makeImage()!
}()

let halation = blurred(glare, sigma: 17)

// Glow: the glare's light thrown onto the tile behind the drive, plus the halation around the lid
let glow = canvas()
glow.draw(blurred(glare, sigma: 87), in: frame)
glow.setBlendMode(.screen)
glow.setAlpha(0.6)
glow.draw(halation, in: frame)
save(glow, "glow.png")

// Drive: one opaque layer, so Liquid Glass traces a single silhouette
let drive = canvas()
drive.addPath(body)
drive.clip()
// Graphite front face, darker where the rounded ends turn away
drive.drawLinearGradient(gradient([(color(0x5A5F70), 0), (color(0x2A2D37), 1)]),
                         start: CGPoint(x: 0, y: lip), end: CGPoint(x: 0, y: floor),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
drive.drawLinearGradient(gradient([(color(0x000000, 0.45), 0), (color(0x000000, 0), 0.12), (color(0x000000, 0), 0.88), (color(0x000000, 0.45), 1)]),
                         start: CGPoint(x: cx - W, y: 0), end: CGPoint(x: cx + W, y: 0), options: [])
// Dark glass lid with the prism and a sheen toward the back
drive.saveGState()
drive.addPath(lid)
drive.clip()
drive.drawLinearGradient(gradient([(color(0x3E4251), 0), (color(0x262833), 1)]),
                         start: CGPoint(x: 0, y: lidTop), end: CGPoint(x: 0, y: lip), options: [])
drive.draw(glare, in: frame)
drive.drawLinearGradient(gradient([(color(0xFFFFFF, 0.22), 0), (color(0xFFFFFF, 0), 0.6)]),
                         start: CGPoint(x: 0, y: lidTop), end: CGPoint(x: 0, y: lip), options: [])
drive.restoreGState()
// Rim, faint at the back and lit along the front lip
drive.saveGState()
drive.addPath(lid.copy(strokingWithWidth: 3, lineCap: .round, lineJoin: .round, miterLimit: 1))
drive.clip()
drive.drawLinearGradient(gradient([(color(0xFFFFFF, 0.2), 0), (color(0xFFFFFF, 0.65), 1)]),
                         start: CGPoint(x: 0, y: lidTop), end: CGPoint(x: 0, y: lip), options: [])
drive.restoreGState()
// Halation spilling over the edges
drive.saveGState()
drive.setBlendMode(.screen)
drive.setAlpha(0.6)
drive.draw(halation, in: frame)
drive.restoreGState()
// Status light
drive.setShadow(offset: .zero, blur: 20, color: color(0x4CF0A8))
drive.setFillColor(color(0x6BF5BC))
drive.fillEllipse(in: CGRect(x: cx + W - 92 - 11, y: floor + H / 2 - 16, width: 22, height: 22))
save(drive, "drive.png")

// Groups are listed front to back. Only the drive takes Liquid Glass highlights and a shadow.
let manifest = """
{
  "fill-specializations" : [
    {
      "value" : {
        "linear-gradient" : [ "extended-srgb:0.16471,0.17647,0.21961,1.00000", "extended-srgb:0.07059,0.07451,0.09412,1.00000" ],
        "orientation" : { "start" : { "x" : 0.5, "y" : 0 }, "stop" : { "x" : 0.5, "y" : 1 } }
      }
    },
    {
      "appearance" : "dark",
      "value" : {
        "linear-gradient" : [ "extended-srgb:0.11373,0.12157,0.15294,1.00000", "extended-srgb:0.03922,0.04314,0.05490,1.00000" ],
        "orientation" : { "start" : { "x" : 0.5, "y" : 0 }, "stop" : { "x" : 0.5, "y" : 1 } }
      }
    }
  ],
  "groups" : [
    {
      "name" : "Drive",
      "layers" : [ { "image-name" : "drive.png", "name" : "drive" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.6 },
      "specular" : true,
      "translucency" : { "enabled" : false, "value" : 0 }
    },
    {
      "name" : "Glow",
      "layers" : [ { "image-name" : "glow.png", "name" : "glow" } ],
      "hidden-specializations" : [ { "appearance" : "tinted", "value" : true } ],
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0 }
    }
  ],
  "supported-platforms" : { "squares" : "shared" }
}
"""
try! manifest.write(to: out.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("wrote \(out.path)")
