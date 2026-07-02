import UIKit

// Single choke point for outbound product links (docs/amazon-app-linking.md).
//
// Amazon URLs are retagged and offered to the OS as universal links first —
// if the Amazon app is installed, iOS routes there with the affiliate tag
// intact (`.universalLinksOnly` opens ONLY when an installed app claims the
// URL). When it isn't (or the user opted out of app-opens), we fall back to
// the caller's in-app browser exactly as before. SFSafariViewController can
// never trigger universal links itself, which is why this branch must happen
// BEFORE presenting the browser.
@MainActor
enum OutboundRouter {
    static func open(
        _ url: URL,
        postId: String,
        source: String,
        fallback: @escaping (URL) -> Void
    ) {
        let outbound = Affiliate.retag(url)

        guard Affiliate.isAppLinkEligible(outbound) else {
            AnalyticsEngine.shared.trackAffiliateClick(
                postId: postId,
                productUrl: outbound.absoluteString,
                source: source,
                destination: "in_app_browser"
            )
            fallback(outbound)
            return
        }

        UIApplication.shared.open(outbound, options: [.universalLinksOnly: true]) { opened in
            Task { @MainActor in
                AnalyticsEngine.shared.trackAffiliateClick(
                    postId: postId,
                    productUrl: outbound.absoluteString,
                    source: source,
                    destination: opened ? "amazon_app" : "in_app_browser"
                )
                if !opened {
                    fallback(outbound)
                }
            }
        }
    }
}
