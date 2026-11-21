import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the BarApp app icons from geometry alone: no design tool, no
// external assets, fixed palette, no timestamps — the same commit always
// renders the same bytes. The script writes the iOS single-size set
// (light, dark, tinted) and the classic macOS multi-size set (each size
// redrawn, on its own rounded-rect plate with transparent surroundings,
// which the system expects) into the asset catalog. CI re-runs this
// script and checks nothing changed.

struct Palette {
    let background: CGColor?
    let glass: CGColor
    let liquid: CGColor
}

let light = Palette(
    background: CGColor(srgbRed: 0.157, green: 0.129, blue: 0.102, alpha: 1),
    glass: CGColor(srgbRed: 0.949, green: 0.910, blue: 0.835, alpha: 1),
    liquid: CGColor(srgbRed: 0.851, green: 0.557, blue: 0.196, alpha: 1))

let dark = Palette(
    background: CGColor(srgbRed: 0.078, green: 0.063, blue: 0.051, alpha: 1),
    glass: CGColor(srgbRed: 0.949, green: 0.910, blue: 0.835, alpha: 1),
    liquid: CGColor(srgbRed: 0.898, green: 0.612, blue: 0.243, alpha: 1))

// Tinted icons are grayscale-with-alpha: the system lays its own
// gradient over the shape, so the glass reads as one silhouette.
let tinted = Palette(
    background: nil,
    glass: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
    liquid: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))

func draw(_ palette: Palette, size: CGFloat, plate: Bool, pixelFloor: CGFloat = 0) -> CGImage {
    let width = Int(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let hasAlpha = plate || palette.background == nil
    let bitmapInfo: UInt32 =
        hasAlpha
        ? CGImageAlphaInfo.premultipliedLast.rawValue
        : CGImageAlphaInfo.noneSkipLast.rawValue
    let context = CGContext(
        data: nil, width: width, height: width, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)!

    let s = size / 1024
    // Hairline geometry gets a floor in pixels; converted back into
    // authoring units here so rect() scales it exactly once.
    func atLeast(_ authored: CGFloat, _ pixels: CGFloat) -> CGFloat {
        max(authored, pixels / s)
    }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        // Geometry below is authored in a 1024-unit canvas with the
        // origin at the top-left; CoreGraphics has its origin at the
        // bottom-left, so y is flipped once here.
        CGRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)
    }

    if let background = palette.background, !plate {
        context.setFillColor(background)
        context.fill(rect(0, 0, 1024, 1024))
    }
    if plate {
        let inset: CGFloat = 100
        context.setFillColor(palette.background!)
        let plate = rect(inset, inset, 1024 - 2 * inset, 1024 - 2 * inset)
        let corner = atLeast(185, 2)
        let rounded = CGPath(
            roundedRect: plate, cornerWidth: corner, cornerHeight: corner,
            transform: nil)
        context.addPath(rounded)
        context.fillPath()
    }

    // A coupe, seen straight on: a half-ellipse bowl with a flat rim,
    // a stem, and a foot. One ellipse inset inside the bowl is the
    // drink. CoreGraphics arcs are circular, so the elliptical bowl is
    // drawn with a vertically scaled context. Angles run upward in
    // CoreGraphics, so the bowl's lower half is drawn counterclockwise
    // from the left rim to the right rim, through the bottom.
    let centerX: CGFloat = 512
    let rimY: CGFloat = 271
    let bowlRx: CGFloat = 260
    let bowlRy: CGFloat = 260

    func drawBowl(rx: CGFloat, ry: CGFloat, fill: CGColor) {
        context.saveGState()
        context.translateBy(x: centerX * s, y: (1024 - rimY) * s)
        context.scaleBy(x: 1, y: ry / rx)
        context.setFillColor(fill)
        let radius = rx * s
        context.addArc(
            center: .zero, radius: radius, startAngle: .pi, endAngle: 0,
            clockwise: false)
        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    // The glass body: bowl in the glass color, then the drink inset.
    drawBowl(rx: bowlRx, ry: bowlRy, fill: palette.glass)
    if size >= 128 {
        context.saveGState()
        context.clip(
            to: rect(
                centerX - bowlRx, rimY, 2 * bowlRx, bowlRy))
        drawBowl(rx: bowlRx - 34, ry: bowlRy - 30, fill: palette.liquid)
        context.restoreGState()
    }

    // Stem and foot, in the glass color. At small sizes the inset drink
    // is skipped so the whole silhouette stays one thick shape.
    context.setFillColor(palette.glass)
    let stemWidth = atLeast(24, pixelFloor)
    context.fill(
        rect(
            centerX - stemWidth / 2, rimY + bowlRy - 4,
            stemWidth, 210))
    context.fill(
        rect(
            centerX - 150, rimY + bowlRy + 196, 300,
            atLeast(26, max(pixelFloor, 2))))

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw NSError(
            domain: "make-icons", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "destination failed for \(url)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(
            domain: "make-icons", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "PNG write failed for \(url)"])
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iosDirectory =
    root
    .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
let macDirectory =
    root
    .appendingPathComponent("App/Resources/Assets.xcassets/AppIconMac.appiconset")
for directory in [iosDirectory, macDirectory] {
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
}

try writePNG(
    draw(light, size: 1024, plate: false), to: iosDirectory.appendingPathComponent("icon-light.png")
)
try writePNG(
    draw(dark, size: 1024, plate: false), to: iosDirectory.appendingPathComponent("icon-dark.png"))
try writePNG(
    draw(tinted, size: 1024, plate: false),
    to: iosDirectory.appendingPathComponent("icon-tinted.png"))

// macOS wants the classic multi-size set; the geometry is redrawn at
// every size so small icons stay crisp instead of downscaled.
let macSizes: [(slot: String, scale: String, pixels: CGFloat)] = [
    ("icon_16x16.png", "1x", 16), ("icon_16x16@2x.png", "2x", 32),
    ("icon_32x32.png", "1x", 32), ("icon_32x32@2x.png", "2x", 64),
    ("icon_128x128.png", "1x", 128), ("icon_128x128@2x.png", "2x", 256),
    ("icon_256x256.png", "1x", 256), ("icon_256x256@2x.png", "2x", 512),
    ("icon_512x512.png", "1x", 512), ("icon_512x512@2x.png", "2x", 1024),
]
func slotSize(_ slot: String) -> String {
    slot.replacingOccurrences(of: "@2x.png", with: "")
        .replacingOccurrences(of: ".png", with: "")
        .replacingOccurrences(of: "icon_", with: "")
}
for spec in macSizes {
    try writePNG(
        draw(dark, size: spec.pixels, plate: true, pixelFloor: max(1.5, spec.pixels / 64)),
        to: macDirectory.appendingPathComponent(spec.slot))
}
let macEntries = macSizes.map { spec -> String in
    """
      {
        "filename" : "\(spec.slot)",
        "idiom" : "mac",
        "scale" : "\(spec.scale)",
        "size" : "\(slotSize(spec.slot))"
      }
    """
}
try """
{
  "images" : [
\(macEntries.joined(separator: ","))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""".write(
    to: macDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

try """
{
  "images" : [
    {
      "filename" : "icon-light.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""".write(
    to: iosDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""".write(
    to: root.appendingPathComponent("App/Resources/Assets.xcassets/Contents.json"),
    atomically: true, encoding: .utf8)

print("icons written")
