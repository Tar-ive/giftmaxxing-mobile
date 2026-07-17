// Rebuilds the 1024x1024 App Store icon from the generated brand master.
// Usage: swift scripts/render-app-icon.swift <output.png>

import Foundation

let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Giftmaxxing/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
task.arguments = [
    "scripts/compose-app-icon.swift",
    "brand-assets/app-icon-master.png",
    out,
]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }

if CommandLine.arguments.count == 1 {
    let files = FileManager.default
    for destination in ["web/public/app-icon.png", "web/public/app-icon-v2.png", "web/app/icon.png"] {
        try? files.removeItem(atPath: destination)
        try files.copyItem(atPath: out, toPath: destination)
    }
}
