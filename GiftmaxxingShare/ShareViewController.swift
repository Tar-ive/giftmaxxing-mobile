import UIKit
import UniformTypeIdentifiers
import OSLog

// "Send to Giftmaxxing" — the Instagram/Pinterest → gift-giving bridge.
//
// Receives an image (screenshot, photo, saved pin) or a URL from any app's
// share sheet, resolves a preview, then asks what to do with it — the start
// of the gifting loop, not a silent save:
//   • Find similar gifts  → visual search in the app
//   • Start a gift pool   → pool creation prefilled with the capture
final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.giftmaxxing.ios"
    private let log = Logger(subsystem: "com.giftmaxxing.ios.share", category: "capture")

    // Resolved capture (image and/or source URL) awaiting the user's choice.
    private var resolvedImageData: Data?
    private var resolvedURLString: String?

    private let card = UIView()
    private let previewView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let searchButton = UIButton(type: .system)
    private let poolButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private let coral = UIColor(red: 1.0, green: 0.42, blue: 0.32, alpha: 1.0)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        resolveAttachments()
    }

    // MARK: - Attachment handling

    private func resolveAttachments() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        // Prefer an image attachment (screenshots, photos, saved pins).
        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            imageProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.resolveImageItem(item)
                }
            }
            return
        }

        // Otherwise a URL (Instagram posts/reels, Pinterest pins, product
        // pages — video shares also arrive as page URLs, and the page's
        // og:image is the video's cover frame).
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                DispatchQueue.main.async {
                    self?.resolveURLItem(item)
                }
            }
            return
        }

        showError()
    }

    private func resolveImageItem(_ item: NSSecureCoding?) {
        var image: UIImage?

        if let url = item as? URL, let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        } else if let direct = item as? UIImage {
            image = direct
        } else if let data = item as? Data {
            image = UIImage(data: data)
        }

        guard let image, let jpeg = downscale(image, maxDimension: 1024)?.jpegData(compressionQuality: 0.85) else {
            showError()
            return
        }

        resolvedImageData = jpeg
        showChoice(preview: UIImage(data: jpeg))
    }

    private func resolveURLItem(_ item: NSSecureCoding?) {
        guard let url = item as? URL else {
            log.error("url attachment did not decode")
            showError()
            return
        }
        resolvedURLString = url.absoluteString

        // Most apps (Instagram included) share a page URL, not pixels — the
        // page's og:image turns the link into a usable capture. 3s budget.
        Task {
            let imageData = await Self.fetchOpenGraphImage(from: url)
            if let imageData {
                self.log.info("og:image resolved (\(imageData.count) bytes)")
                self.resolvedImageData = imageData
            } else {
                self.log.info("no og:image — url-only capture")
            }
            self.showChoice(preview: imageData.flatMap(UIImage.init(data:)))
        }
    }

    // MARK: - Actions

    @objc private func searchTapped() {
        commit(intent: "search", doneMessage: "Open Giftmaxxing for matches")
    }

    @objc private func poolTapped() {
        commit(intent: "pool", doneMessage: "Pool draft ready — open Giftmaxxing")
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func commit(intent: String, doneMessage: String) {
        let saved = writeInbox(imageData: resolvedImageData, url: resolvedURLString, intent: intent)
        if saved {
            showDone(message: doneMessage)
        } else {
            showError()
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
    private func writeInbox(imageData: Data?, url: String?, intent: String) -> Bool {
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
            "intent": intent,
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

        previewView.contentMode = .scaleAspectFill
        previewView.clipsToBounds = true
        previewView.layer.cornerRadius = 14
        previewView.backgroundColor = .secondarySystemBackground
        previewView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Add to Giftmaxxing"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = "Reading what you shared…"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        configure(searchButton, title: "🔍  Find similar gifts", filled: true)
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)

        configure(poolButton, title: "🤝  Start a gift pool", filled: false)
        poolButton.addTarget(self, action: #selector(poolTapped), for: .touchUpInside)

        cancelButton.setTitle("Not now", for: .normal)
        cancelButton.setTitleColor(.secondaryLabel, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        // Buttons disabled until the capture resolves.
        setButtons(enabled: false)

        [previewView, titleLabel, subtitleLabel, spinner, searchButton, poolButton, cancelButton].forEach {
            card.addSubview($0)
        }

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 300),

            previewView.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            previewView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 132),
            previewView.heightAnchor.constraint(equalToConstant: 132),

            spinner.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            searchButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            searchButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            searchButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            searchButton.heightAnchor.constraint(equalToConstant: 46),

            poolButton.topAnchor.constraint(equalTo: searchButton.bottomAnchor, constant: 8),
            poolButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            poolButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            poolButton.heightAnchor.constraint(equalToConstant: 46),

            cancelButton.topAnchor.constraint(equalTo: poolButton.bottomAnchor, constant: 6),
            cancelButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
    }

    private func configure(_ button: UIButton, title: String, filled: Bool) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = filled ? coral : coral.withAlphaComponent(0.14)
        config.baseForegroundColor = filled ? .white : coral
        config.cornerStyle = .large
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setButtons(enabled: Bool) {
        searchButton.isEnabled = enabled
        poolButton.isEnabled = enabled
        searchButton.alpha = enabled ? 1 : 0.5
        poolButton.alpha = enabled ? 1 : 0.5
    }

    // MARK: - States

    private func showChoice(preview: UIImage?) {
        spinner.stopAnimating()
        setButtons(enabled: true)

        if let preview {
            previewView.image = preview
            subtitleLabel.text = "What do you want to do with it?"
        } else {
            // URL-only capture (private post) — still actionable.
            previewView.image = nil
            previewView.backgroundColor = coral.withAlphaComponent(0.12)
            subtitleLabel.text = "Couldn't load a preview — you can still save it."
        }
    }

    private func showDone(message: String) {
        titleLabel.text = "Added to Giftmaxxing ✓"
        subtitleLabel.text = message
        setButtons(enabled: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError() {
        spinner.stopAnimating()
        titleLabel.text = "Couldn't read that"
        subtitleLabel.text = "Try sharing an image or link."
        setButtons(enabled: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
