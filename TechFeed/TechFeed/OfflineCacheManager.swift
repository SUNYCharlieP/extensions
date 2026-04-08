import Foundation

class OfflineCacheManager {
    static let shared = OfflineCacheManager()

    private let fileManager = FileManager.default
    private let cacheDir: URL

    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = cachesURL.appendingPathComponent("arca_offline", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Cache article HTML for offline reading.
    func cacheArticle(_ item: FeedItem) {
        let key = cacheKey(for: item)
        let fileURL = cacheDir.appendingPathComponent(key)

        guard !fileManager.fileExists(atPath: fileURL.path) else { return }

        var request = URLRequest(url: item.url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            try? data.write(to: fileURL)

            // Track cached URLs
            DispatchQueue.main.async {
                var cached = self.cachedURLs
                cached.insert(item.url.absoluteString)
                UserDefaults.standard.set(Array(cached), forKey: "arca_cached_urls")
            }
        }.resume()
    }

    /// Check if an article is available offline.
    func isCached(_ item: FeedItem) -> Bool {
        let key = cacheKey(for: item)
        let fileURL = cacheDir.appendingPathComponent(key)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Get cached HTML data for an article.
    func cachedData(for item: FeedItem) -> Data? {
        let key = cacheKey(for: item)
        let fileURL = cacheDir.appendingPathComponent(key)
        return try? Data(contentsOf: fileURL)
    }

    /// Cache bookmarked articles for offline access.
    func cacheBookmarkedArticles(from items: [FeedItem]) {
        let bookmarked = items.filter { BookmarkManager.shared.isBookmarked($0) }
        for item in bookmarked {
            cacheArticle(item)
        }
    }

    /// Clear old cache entries (older than 7 days).
    func pruneOldCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)

        for file in files {
            guard let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                  let created = attrs[.creationDate] as? Date,
                  created < sevenDaysAgo else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private var cachedURLs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "arca_cached_urls") ?? [])
    }

    private func cacheKey(for item: FeedItem) -> String {
        guard let data = item.url.absoluteString.data(using: .utf8) else {
            return "\(item.url.absoluteString.hashValue).html"
        }
        let hash = data.map { String(format: "%02x", $0) }.joined()
        return String(hash.prefix(40)) + ".html"
    }
}
