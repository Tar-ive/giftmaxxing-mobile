import UIKit
import UniformTypeIdentifiers
import OSLog

// "Send to Giftmaxxing" — the Instagram/Pinterest → Amazon bridge.
//
// Receives an image (screenshot, photo, saved pin) or a URL from any app's
// share sheet, writes it to the app-group inbox, and shows a quick
// confirmation. The main app picks it up on next foreground and runs visual
// search over the gift index automatically.
final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.giftmaxxing.ios"
    private let log = Logger(subsystem: "com.giftmaxxing.ios.share", category: "capture")

    private let card = UIView()
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        processAttachments()
    }

    // MARK: - Attachment handling

    private func processAttachments() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(success: false)
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        // Prefer an image attachment (screenshots, photos, saved pins).
        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            imageProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.handleImageItem(item)
                }
            }
            return
        }

        // Otherwise take a URL (Instagram post links, Pinterest pins, product pages).
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.handleURLItem(item)
                }
            }
            return
        }

        finish(success: false)
    }

    private func handleImageItem(_ item: NSSecureCoding?) {
        var image: UIImage?

        if let url = item as? URL, let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        } else if let direct = item as? UIImage {
            image = direct
        } else if let data = item as? Data {
            image = UIImage(data: data)
        }

        guard let image, let jpeg = downscale(image, maxDimension: 1024)?.jpegData(compressionQuality: 0.85) else {
            finish(success: false)
            return
        }

        let saved = writeInbox(imageData: jpeg, url: nil)
        finish(success: saved, message: saved ? "Open Giftmaxxing for matches" : "")
    }

    private func handleURLItem(_ item: NSSecureCoding?) {
        guard let url = item as? URL else {
            log.error("url attachment did not decode")
            finish(success: false)
            return
        }

        // Most apps (Instagram included) share a page URL, not pixels. Try to
        // resolve the page's og:image so the capture becomes a real visual
        // search; fall back to saving the bare URL. Hard 3s budget — share
        // extensions get killed quickly.
        Task {
            if let imageData = await Self.fetchOpenGraphImage(from: url) {
                self.log.info("og:image resolved (\(imageData.count) bytes)")
                let saved = self.writeInbox(imageData: imageData, url: url.absoluteString)
                self.finish(success: saved, message: saved ? "Open Giftmaxxing for matches" : "")
            } else {
                self.log.info("no og:image — saving bare url")
                let saved = self.writeInbox(imageData: nil, url: url.absoluteString)
                self.finish(success: saved, message: saved ? "Open Giftmaxxing — tip inside" : "")
            }
        }
    }

    // Fetch the shared page and pull og:image / twitter:image. Works for
    // Pinterest pins, product pages, and public Instagram posts.
    private static func fetchOpenGraphImage(from url: URL) async -> Data? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        // A browsery UA gets og-tags from pages that hide them from bots.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, _) = try? await session.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }

        let patterns = [
            "property=\"og:image\"[^>]*content=\"([^\"]+)\"",
            "content=\"([^\"]+)\"[^>]*property=\"og:image\"",
            "name=\"twitter:image\"[^>]*content=\"([^\"]+)\"",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html) {
                let raw = String(html[range])
                    .replacingOccurrences(of: "&amp;", with: "&")
                guard let imageURL = URL(string: raw),
                      let (imageData, _) = try? await session.data(from: imageURL),
                      imageData.count > 5_000,
                      UIImage(data: imageData) != nil else { continue }
                return imageData
            }
        }
        return nil
    }

    // MARK: - App-group inbox

    @discardableResult
    private func writeInbox(imageData: Data?, url: String?) -> Bool {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            log.error("app-group container unavailable — capture not saved")
            return false
        }
        log.info("writing capture: image=\(imageData != nil) url=\(url != nil)")

        let inbox = container.appendingPathComponent("capture-inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        if let imageData {
            do {
                try imageData.write(to: inbox.appendingPathComponent("capture.jpg"), options: .atomic)
            } catch {
                log.error("image write failed: \(error.localizedDescription)")
                return false
            }
        } else {
            try? FileManager.default.removeItem(at: inbox.appendingPathComponent("capture.jpg"))
        }

        let meta: [String: Any] = [
            "type": imageData != nil ? "image" : "url",
            "url": url ?? "",
            "ts": Date().timeIntervalSince1970,
        ]
        guard let metaData = try? JSONSerialization.data(withJSONObject: meta),
              (try? metaData.write(to: inbox.appendingPathComponent("capture.json"), options: .atomic)) != nil else {
            log.error("meta write failed")
            return false
        }
        return true
    }

    private func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - UI

    private func buildUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)

        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 22
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        iconLabel.text = "🎁"
        iconLabel.font = .systemFont(ofSize: 44)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Sending to Giftmaxxing"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "One sec…"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconLabel)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 260),

            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            iconLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
        ])
    }

    private func finish(success: Bool, message: String = "") {
        if success {
            titleLabel.text = "Added to Giftmaxxing ✓"
            subtitleLabel.text = message
        } else {
            titleLabel.text = "Couldn't read that"
            subtitleLabel.text = "Try sharing an image or link."
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
