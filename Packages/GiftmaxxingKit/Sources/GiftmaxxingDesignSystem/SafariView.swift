// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore
import SafariServices

// In-app browser (SFSafariViewController) — product links open inside the app
// like Amazon/Instagram instead of bouncing the user out to Safari.
public struct SafariView: UIViewControllerRepresentable {
    public let url: URL

    public init(
        url: URL
    ) {
        self.url = url
    }


    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(Color.coral)
        controller.dismissButtonStyle = .close
        return controller
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// Identifiable URL wrapper for sheet(item:) presentation.
public struct BrowserTarget: Identifiable {
    public let url: URL

    public init(
        url: URL
    ) {
        self.url = url
    }

    public var id: String { url.absoluteString }
}


#endif
