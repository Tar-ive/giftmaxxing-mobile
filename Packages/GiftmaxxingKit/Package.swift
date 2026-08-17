// swift-tools-version: 5.9
import PackageDescription

// GiftmaxxingKit — the parts of the app that aren't the app.
//
// The rule that makes this worth having: **nothing in here may import the app
// target.** Dependencies point one way (app → Recommendation → Core), so a
// layering mistake is a compile error rather than a review comment.
//
// Core is pure value types (Foundation only, no SwiftUI). Recommendation is the
// on-device ranking stack, which is why it can be tested without booting a
// simulator or building 78 view files.
let package = Package(
    name: "GiftmaxxingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GiftmaxxingCore", targets: ["GiftmaxxingCore"]),
        .library(name: "GiftmaxxingRecommendation", targets: ["GiftmaxxingRecommendation"]),
    ],
    targets: [
        .target(name: "GiftmaxxingCore"),
        .target(
            name: "GiftmaxxingRecommendation",
            dependencies: ["GiftmaxxingCore"]
        ),
        .testTarget(
            name: "GiftmaxxingRecommendationTests",
            dependencies: ["GiftmaxxingRecommendation", "GiftmaxxingCore"]
        ),
    ]
)
