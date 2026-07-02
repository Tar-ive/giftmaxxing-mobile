import SwiftUI
import SafariServices

// In-app browser (SFSafariViewController) — product links open inside the app
// like Amazon/Instagram instead of bouncing the user out to Safari.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(Color.coral)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// Identifiable URL wrapper for sheet(item:) presentation.
struct BrowserTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
