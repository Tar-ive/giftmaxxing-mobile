// Composes the 1024x1024 App Store icon from the brand logo: the artwork is
// centered on a canvas filled with the logo's own background color (sampled
// from its corner pixel, so the edges blend seamlessly). Output is opaque —
// App Store Connect rejects icons with an alpha channel.
// Usage: swift scripts/compose-app-icon.swift <logo.png> <output.png>

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: compose-app-icon.swift <logo.png> <output.png>")
    exit(1)
}

let size = 1024
guard
    let logoData = FileManager.default.contents(atPath: args[1]),
    let logo = NSBitmapImageRep(data: logoData),
    let logoCG = logo.cgImage
else { fatalError("cannot read logo \(args[1])") }

guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("no context") }

// Full-bleed the logo horizontally; edge-extend its own first/last pixel
// rows to fill the bands above and below — truly seamless, even though the
// source background carries a subtle vignette.
let logoW = CGFloat(logoCG.width)
let logoH = CGFloat(logoCG.height)
let drawW = CGFloat(size)
let drawH = (logoH * (drawW / logoW)).rounded()
let bandH = ((CGFloat(size) - drawH) / 2).rounded(.up)

ctx.interpolationQuality = .high
if bandH > 0,
   let topRow = logoCG.cropping(to: CGRect(x: 0, y: 0, width: logoCG.width, height: 1)),
   let bottomRow = logoCG.cropping(to: CGRect(x: 0, y: logoCG.height - 1, width: logoCG.width, height: 1)) {
    // CG coords: y=0 is the BOTTOM of the canvas.
    ctx.draw(topRow, in: CGRect(x: 0, y: CGFloat(size) - bandH, width: drawW, height: bandH))
    ctx.draw(bottomRow, in: CGRect(x: 0, y: 0, width: drawW, height: bandH))
}
ctx.draw(logoCG, in: CGRect(
    x: 0,
    y: (CGFloat(size) - drawH) / 2,
    width: drawW,
    height: drawH
))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) from \(args[1]) (\(size)x\(size), opaque)")
