// Renders the 1024x1024 App Store marketing icon: the MaxiIcon brand mark
// (coral gradient + gift emoji) at full bleed, flattened to opaque RGB —
// App Store Connect rejects icons with an alpha channel.
// Usage: swift scripts/render-app-icon.swift <output.png>

import AppKit
import CoreText

let size = CGFloat(1024)
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Giftmaxxing/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let ctx = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("no context") }

// Brand gradient (Theme.swift coral #FB6F52 → MaxiIcon's #FF9A76), diagonal.
func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}
let colors = [rgb(0xFB6F52), rgb(0xFF9A76)]
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: colors as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// Soft white circle behind the glyph — mirrors the in-app MaxiIcon badge.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
ctx.fillEllipse(in: CGRect(x: size * 0.13, y: size * 0.13, width: size * 0.74, height: size * 0.74))

// The gift — Apple Color Emoji via CoreText, centered optically (slightly up).
let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 560, nil)
let attr = NSAttributedString(string: "🎁", attributes: [
    kCTFontAttributeName as NSAttributedString.Key: font
])
let line = CTLineCreateWithAttributedString(attr)
let bounds = CTLineGetImageBounds(line, ctx)
ctx.textPosition = CGPoint(
    x: (size - bounds.width) / 2 - bounds.minX,
    y: (size - bounds.height) / 2 - bounds.minY + size * 0.01
)
CTLineDraw(line, ctx)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(Int(size))x\(Int(size)), opaque)")
