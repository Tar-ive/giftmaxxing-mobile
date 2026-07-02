import UIKit
import UniformTypeIdentifiers

// "Send to Giftmaxxing" — the Instagram/Pinterest → Amazon bridge.
//
// Receives an image (screenshot, photo, saved pin) or a URL from any app's
// share sheet, writes it to the app-group inbox, and shows a quick
// confirmation. The main app picks it up on next foreground and runs visual
// search over the gift index automatically.
final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.giftmaxxing.ios"

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

        writeInbox(imageData: jpeg, url: nil)
        finish(success: true, message: "Finding similar gifts…")
    }

    private func handleURLItem(_ item: NSSecureCoding?) {
        guard let url = item as? URL else {
            finish(success: false)
            return
        }
        writeInbox(imageData: nil, url: url.absoluteString)
        finish(success: true, message: "Saved — open Giftmaxxing")
    }

    // MARK: - App-group inbox

    private func writeInbox(imageData: Data?, url: String?) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return }

        let inbox = container.appendingPathComponent("capture-inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        if let imageData {
            try? imageData.write(to: inbox.appendingPathComponent("capture.jpg"), options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: inbox.appendingPathComponent("capture.jpg"))
        }

        let meta: [String: Any] = [
            "type": imageData != nil ? "image" : "url",
            "url": url ?? "",
            "ts": Date().timeIntervalSince1970,
        ]
        if let metaData = try? JSONSerialization.data(withJSONObject: meta) {
            try? metaData.write(to: inbox.appendingPathComponent("capture.json"), options: .atomic)
        }
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
