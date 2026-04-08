import Foundation
import CryptoKit

class OfflineCacheManager {
    static let shared = OfflineCacheManager()

    private let fileManager = FileManager.default
    private let cacheDir: URL
    private let trackingQueue = DispatchQueue(label: "com.arca.cache.tracking")
    /// In-memory copy of tracked URLs — all reads/writes happen on trackingQueue.
    private var _trackedURLs: Set<String>

    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = cachesURL.appendingPathComponent("arca_offline", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        _trackedURLs = Set(UserDefaults.standard.stringArray(forKey: "arca_cached_urls") ?? [])
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

            // Track cached URLs — in-memory set prevents read-after-write race
            self.trackingQueue.async {
                self._trackedURLs.insert(item.url.absoluteString)
                UserDefaults.standard.set(Array(self._trackedURLs), forKey: "arca_cached_urls")
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
    /// `bookmarkedURLs` must be passed in — callers should snapshot it on the main thread
    /// before dispatching to a background queue, since BookmarkManager is not thread-safe.
    func cacheBookmarkedArticles(from items: [FeedItem], bookmarkedURLs: Set<String>) {
        let bookmarked = items.filter { bookmarkedURLs.contains($0.url.absoluteString) }
        for item in bookmarked {
            cacheArticle(item)
        }
    }

    /// Clear old cache entries (older than 7 days).
    func pruneOldCache() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        var didPrune = false

        for file in files {
            guard let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                  let modified = attrs[.modificationDate] as? Date,
                  modified < sevenDaysAgo else { continue }
            try? fileManager.removeItem(at: file)
            didPrune = true
        }

        // Sync tracked URLs with actual files on disk.
        // Can't map hashed filenames back to URLs, so we verify each tracked URL
        // still has a corresponding file. isCached() is the source of truth.
        if didPrune {
            trackingQueue.async {
                let surviving = self._trackedURLs.filter { urlString in
                    guard URL(string: urlString) != nil else { return false }
                    let data = Data(urlString.utf8)
                    let hash = SHA256.hash(data: data)
                    let key = hash.prefix(20).map { String(format: "%02x", $0) }.joined() + ".html"
                    return self.fileManager.fileExists(atPath: self.cacheDir.appendingPathComponent(key).path)
                }
                self._trackedURLs = surviving
                UserDefaults.standard.set(Array(surviving), forKey: "arca_cached_urls")
            }
        }
    }

    private func cacheKey(for item: FeedItem) -> String {
        let data = Data(item.url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.prefix(20).map { String(format: "%02x", $0) }.joined() + ".html"
    }
}
