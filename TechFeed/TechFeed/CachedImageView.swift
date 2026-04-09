import SwiftUI
import ImageIO

/// Simple in-memory image cache backed by NSCache.
/// Prevents AsyncImage from re-downloading images on every scroll.
/// Images are downsampled to screen-appropriate sizes to prevent OOM crashes.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 40 * 1024 * 1024 // 40 MB
        // Auto-evict on memory pressure
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak cache] _ in
            cache?.removeAllObjects()
        }
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Downsample image data to a max pixel dimension.
    /// Uses ImageIO to decode at reduced size — never loads full bitmap into memory.
    static func downsample(data: Data, maxPixels: CGFloat = 800) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Drop-in replacement for AsyncImage with in-memory caching.
/// Images survive scroll recycling without re-downloading.
struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var currentTask: URLSessionDataTask?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else if isLoading {
                Color(.tertiarySystemGroupedBackground)
            } else {
                Color(.tertiarySystemGroupedBackground)
                    .onAppear { loadImage() }
            }
        }
        .onChange(of: url) { newURL in
            currentTask?.cancel()
            currentTask = nil
            image = nil
            isLoading = false
            if newURL != nil { loadImage() }
        }
    }

    private func loadImage() {
        guard let url = url, !isLoading else { return }

        // Check cache first
        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        isLoading = true
        let capturedURL = url
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            guard let uiImage = ImageCache.downsample(data: data) else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            ImageCache.shared.store(uiImage, for: capturedURL)
            DispatchQueue.main.async {
                guard self.url == capturedURL else { return }
                self.image = uiImage
                self.isLoading = false
                self.currentTask = nil
            }
        }
        self.currentTask = task
        task.resume()
    }
}
