#!/usr/bin/env swift

import AppKit

struct Shot {
    let file: String
    let title: String
    let subtitle: String
    let background: NSColor
    let foreground: NSColor
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let raw = root.appendingPathComponent("build/appstore-shots")
let output = root.appendingPathComponent("appstore-assets/6.9-inch")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let shots = [
    Shot(
        file: "01-home.png",
        title: "Thoughtful gifts,\nmade easy.",
        subtitle: "Discover ideas shaped around every person you love.",
        background: NSColor(calibratedRed: 0.969, green: 0.949, blue: 0.922, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.10, alpha: 1)
    ),
    Shot(
        file: "02-swipe.png",
        title: "Teach it\ntheir taste.",
        subtitle: "Swipe through ideas and make every suggestion more personal.",
        background: NSColor(calibratedWhite: 0.075, alpha: 1),
        foreground: .white
    ),
    Shot(
        file: "03-post.png",
        title: "Share finds\nworth gifting.",
        subtitle: "Post photos and videos that inspire someone’s next gift.",
        background: NSColor(calibratedRed: 1, green: 0.941, blue: 0.925, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.10, alpha: 1)
    ),
    Shot(
        file: "04-circles.png",
        title: "Plan together,\nwithout the chaos.",
        subtitle: "Bring friends into circles and make the moment count.",
        background: NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.945, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.10, alpha: 1)
    ),
    Shot(
        file: "05-you.png",
        title: "Remember what\nthey really love.",
        subtitle: "Keep tastes, sizes, posts, and gift ideas in one thoughtful profile.",
        background: NSColor(calibratedRed: 0.969, green: 0.949, blue: 0.922, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.10, alpha: 1)
    ),
]

func drawText(
    _ text: String,
    rect: NSRect,
    font: NSFont,
    color: NSColor,
    lineHeight: CGFloat? = nil
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    (text as NSString).draw(
        in: rect,
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    )
}

for (index, shot) in shots.enumerated() {
    guard let screen = NSImage(contentsOf: raw.appendingPathComponent(shot.file)),
          let icon = NSImage(contentsOf: root.appendingPathComponent(
            "Giftmaxxing/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
          )) else {
        fatalError("Missing source image for \(shot.file)")
    }

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1320,
        pixelsHigh: 2868,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create canvas")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    shot.background.setFill()
    NSRect(x: 0, y: 0, width: 1320, height: 2868).fill()

    let iconRect = NSRect(x: 118, y: 2660, width: 82, height: 82)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: iconRect, xRadius: 18, yRadius: 18).addClip()
    icon.draw(in: iconRect)
    NSGraphicsContext.restoreGraphicsState()
    drawText(
        "giftmaxxing",
        rect: NSRect(x: 224, y: 2674, width: 500, height: 54),
        font: .systemFont(ofSize: 36, weight: .bold),
        color: shot.foreground
    )
    drawText(
        shot.title,
        rect: NSRect(x: 118, y: 2220, width: 1084, height: 330),
        font: .systemFont(ofSize: 100, weight: .bold),
        color: shot.foreground,
        lineHeight: 104
    )
    drawText(
        shot.subtitle,
        rect: NSRect(x: 122, y: 2115, width: 1030, height: 90),
        font: .systemFont(ofSize: 37, weight: .regular),
        color: shot.foreground.withAlphaComponent(0.68)
    )

    let screenRect = NSRect(x: 176, y: -110, width: 968, height: 2103)
    let borderRect = screenRect.insetBy(dx: -14, dy: -14)
    let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: 78, yRadius: 78)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    shadow.shadowBlurRadius = 46
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor.black.setFill()
    borderPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let clip = NSBezierPath(roundedRect: screenRect, xRadius: 66, yRadius: 66)
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    screen.draw(in: screenRect)
    NSGraphicsContext.restoreGraphicsState()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        fatalError("Could not encode \(shot.file)")
    }
    let destination = output.appendingPathComponent(String(format: "%02d.png", index + 1))
    try png.write(to: destination)
    print(destination.path)
}
