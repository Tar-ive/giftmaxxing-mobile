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
        .library(name: "GiftmaxxingNetworking", targets: ["GiftmaxxingNetworking"]),
        .library(name: "GiftmaxxingDesignSystem", targets: ["GiftmaxxingDesignSystem"]),
    ],
    targets: [
        .target(name: "GiftmaxxingCore"),
        .target(
            name: "GiftmaxxingRecommendation",
            dependencies: ["GiftmaxxingCore"]
        ),
        .target(
            name: "GiftmaxxingNetworking",
            dependencies: ["GiftmaxxingCore"]
        ),
        // Image loading lives here rather than in Networking: ImageLoader is an
        // NSCache in front of CachedAsyncImage, and splitting them would add a
        // dependency edge between two siblings for the sake of one view.
        // firefox-ios makes the same call — its SiteImageView both fetches and
        // renders.
        // iOS-only (UIColor trait resolution), so its tests live in the app's
        // simulator suite rather than the macOS-native `swift test` run.
        .target(
            name: "GiftmaxxingDesignSystem",
            dependencies: ["GiftmaxxingCore"]
        ),
        .testTarget(
            name: "GiftmaxxingNetworkingTests",
            dependencies: ["GiftmaxxingNetworking", "GiftmaxxingCore"]
        ),
        .testTarget(
            name: "GiftmaxxingRecommendationTests",
            dependencies: ["GiftmaxxingRecommendation", "GiftmaxxingCore"]
        ),
    ]
)
