// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore

public actor ImageLoader {
    public static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024
    }

    public func load(url: String, width: Int? = nil) async -> UIImage? {
        let key = cacheKey(url: url, width: width)
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        if let existingTask = inFlightTasks[key] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> {
            guard let imageUrl = buildURL(base: url, width: width) else { return nil }
            do {
                let data = try await imageData(from: imageUrl)
                guard let image = UIImage(data: data) else { return nil }
                cache.setObject(image, forKey: cacheKey, cost: data.count)
                return image
            } catch {
                return nil
            }
        }

        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks.removeValue(forKey: key)
        return result
    }

    public func prefetch(urls: [String], width: Int? = nil) {
        for url in urls {
            let key = cacheKey(url: url, width: width)
            let cacheKey = key as NSString
            if cache.object(forKey: cacheKey) != nil { continue }
            if inFlightTasks[key] != nil { continue }

            let task = Task<UIImage?, Never> {
                guard let imageUrl = buildURL(base: url, width: width) else { return nil }
                do {
                    let data = try await imageData(from: imageUrl)
                    guard let image = UIImage(data: data) else { return nil }
                    cache.setObject(image, forKey: cacheKey, cost: data.count)
                    return image
                } catch {
                    return nil
                }
            }
            inFlightTasks[key] = task
            Task {
                _ = await task.value
                inFlightTasks.removeValue(forKey: key)
            }
        }
    }

    public func clearCache() {
        cache.removeAllObjects()
    }

    private func buildURL(base: String, width: Int?) -> URL? {
        if base.hasPrefix("bundle:///") {
            let filename = String(base.dropFirst("bundle:///".count))
            let resource = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            return Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Curated")
                ?? Bundle.main.url(forResource: resource, withExtension: ext)
        }
        guard var url = URL(string: base) else { return nil }
        if let width, let cloudFrontBase = cloudFrontURL(for: base) {
            var components = URLComponents(url: cloudFrontBase, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "w", value: "\(width)"))
            queryItems.append(URLQueryItem(name: "q", value: "80"))
            components?.queryItems = queryItems
            url = components?.url ?? url
        }
        return url
    }

    private func imageData(from url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        return try await session.data(from: url).0
    }

    // A board thumbnail and a swipe card can share a source URL but need
    // different decoded image sizes. Keeping width in the key prevents the
    // large swipe prefetch from being reused by the board list.
    private func cacheKey(url: String, width: Int?) -> String {
        "\(url)|w:\(width.map { String($0) } ?? "original")"
    }

    private func cloudFrontURL(for urlString: String) -> URL? {
        guard urlString.contains("cloudfront.net") || urlString.contains("giftmaxxing") else {
            return nil
        }
        return URL(string: urlString)
    }
}

public struct CachedAsyncImage: View {
    public let url: String?
    public var width: Int? = nil
    public var contentMode: ContentMode = .fill
    /// Reports the decoded image's width/height so callers can size
    /// user-uploaded media to its real shape (see MediaAspect).
    public var onAspect: ((CGFloat) -> Void)? = nil

    public init(
        url: String? = nil,
        width: Int? = nil,
        contentMode: ContentMode = .fill,
        onAspect: ((CGFloat) -> Void)? = nil,
        showsFailurePlaceholder: Bool = true
    ) {
        self.url = url
        self.width = width
        self.contentMode = contentMode
        self.onAspect = onAspect
        self.showsFailurePlaceholder = showsFailurePlaceholder
    }

    /// Avatars draw their own fallback underneath, so a failed load should
    /// reveal it rather than stamp a broken-photo glyph on top.
    public var showsFailurePlaceholder = true

    @State private var image: UIImage?
    @State private var isLoading = true

    public var body: some View {
        Group {
            if let image {
                if contentMode == .fill {
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else if isLoading {
                if showsFailurePlaceholder {
                    Rectangle()
                        .fill(Color.cream)
                        .overlay {
                            ProgressView()
                                .tint(Color.coral)
                        }
                } else {
                    Color.clear
                }
            } else if showsFailurePlaceholder {
                Rectangle()
                    .fill(Color.cream)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url, !url.isEmpty else {
                isLoading = false
                return
            }
            image = await ImageLoader.shared.load(url: url, width: width)
            isLoading = false
            if let size = image?.size, size.height > 0 {
                onAspect?(size.width / size.height)
            }
        }
    }
}


#endif
