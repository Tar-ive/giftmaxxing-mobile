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

        // 1. Amazon's own URL scheme — deterministic app-open when installed
        //    (universal links silently fail once the user has ever picked
        //    "open in browser" for amazon.com; the scheme has no such state).
        //    The Amazon app preserves the affiliate tag on web-style scheme URLs.
        if let schemeURL = amazonSchemeURL(for: outbound) {
            UIApplication.shared.open(schemeURL, options: [:]) { opened in
                Task { @MainActor in
                    if opened {
                        AnalyticsEngine.shared.trackAffiliateClick(
                            postId: postId,
                            productUrl: outbound.absoluteString,
                            source: source,
                            destination: "amazon_app"
                        )
                    } else {
                        // App not installed — straight to the in-app browser.
                        AnalyticsEngine.shared.trackAffiliateClick(
                            postId: postId,
                            productUrl: outbound.absoluteString,
                            source: source,
                            destination: "in_app_browser"
                        )
                        fallback(outbound)
                    }
                }
            }
            return
        }

        // 2. Non-schemeable Amazon URL (shortlinks etc.): universal link try,
        //    then browser.
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

    // https://www.amazon.com/dp/B0... → com.amazon.mobile.shopping.web://amazon.com/dp/B0...
    private static func amazonSchemeURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "amazon.com" || host.hasSuffix(".amazon.com") else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        return URL(string: "com.amazon.mobile.shopping.web://amazon.com\(path)\(query)")
    }
}
