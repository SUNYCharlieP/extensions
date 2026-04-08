import SwiftUI

/// Simple in-memory image cache backed by NSCache.
/// Prevents AsyncImage from re-downloading images on every scroll.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

/// Drop-in replacement for AsyncImage with in-memory caching.
/// Images survive scroll recycling without re-downloading.
struct CachedAsyncImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var isLoading = false

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
    }

    private func loadImage() {
        guard let url = url else { return }

        // Check cache first
        if let cached = ImageCache.shared.image(for: url) {
            self.image = cached
            return
        }

        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let uiImage = UIImage(data: data) else {
                DispatchQueue.main.async { isLoading = false }
                return
            }
            ImageCache.shared.store(uiImage, for: url)
            DispatchQueue.main.async {
                self.image = uiImage
                self.isLoading = false
            }
        }.resume()
    }
}
