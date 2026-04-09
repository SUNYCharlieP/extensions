import Foundation

class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "arca_bookmarks"
    private let itemsKey = "arca_bookmarked_items"
    /// Serial queue prevents out-of-order UserDefaults writes.
    private let persistQueue = DispatchQueue(label: "com.arca.bookmarks.persist")

    @Published var bookmarkedURLs: Set<String>
    /// Persisted FeedItem data for bookmarks that have aged out of the live feed
    private var persistedItems: [String: FeedItem] = [:]

    private init() {
        bookmarkedURLs = Set(defaults.stringArray(forKey: bookmarkKey) ?? [])
        loadPersistedItems()
    }

    func isBookmarked(_ item: FeedItem) -> Bool {
        bookmarkedURLs.contains(item.url.absoluteString)
    }

    func toggle(_ item: FeedItem) {
        let url = item.url.absoluteString
        if bookmarkedURLs.contains(url) {
            bookmarkedURLs.remove(url)
            persistedItems.removeValue(forKey: url)
        } else {
            bookmarkedURLs.insert(url)
            persistedItems[url] = item
        }
        let snapshot = Array(bookmarkedURLs)
        let items = persistedItems
        persistQueue.async {
            UserDefaults.standard.set(snapshot, forKey: self.bookmarkKey)
            self.savePersistedItems(items)
        }
    }

    /// Returns all bookmarked items, merging live feed items with persisted ones
    func allBookmarkedItems(liveItems: [FeedItem]) -> [FeedItem] {
        let liveBookmarked = liveItems.filter { isBookmarked($0) }
        let liveURLs = Set(liveBookmarked.map { $0.url.absoluteString })

        // Add persisted items that aren't in the live feed
        var result = liveBookmarked
        for url in bookmarkedURLs {
            if !liveURLs.contains(url), let item = persistedItems[url] {
                result.append(item)
            }
        }
        return result.sorted { $0.pubDate > $1.pubDate }
    }

    /// Merge bookmarks from cloud sync.
    func mergeFromCloud(_ urls: Set<String>) {
        let merged = bookmarkedURLs.union(urls)
        guard merged != bookmarkedURLs else { return }
        bookmarkedURLs = merged
        let snapshot = Array(bookmarkedURLs)
        let key = bookmarkKey
        persistQueue.async {
            UserDefaults.standard.set(snapshot, forKey: key)
        }
    }

    // MARK: - Item Persistence

    private func loadPersistedItems() {
        guard let data = defaults.data(forKey: itemsKey),
              let decoded = try? JSONDecoder().decode([String: CodableFeedItem].self, from: data) else { return }
        persistedItems = decoded.mapValues { $0.toFeedItem() }
    }

    private func savePersistedItems(_ items: [String: FeedItem]) {
        let codable = items.mapValues { CodableFeedItem(from: $0) }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
    }
}

/// Codable wrapper for FeedItem persistence
private struct CodableFeedItem: Codable {
    let title: String
    let source: String
    let url: String
    let imageURL: String?
    let pubDate: Date
    let itemDescription: String
    let category: String
    let contentHTML: String

    init(from item: FeedItem) {
        self.title = item.title
        self.source = item.source
        self.url = item.url.absoluteString
        self.imageURL = item.imageURL?.absoluteString
        self.pubDate = item.pubDate
        self.itemDescription = item.itemDescription
        self.category = item.category
        self.contentHTML = item.contentHTML
    }

    func toFeedItem() -> FeedItem {
        var item = FeedItem(
            title: title,
            itemDescription: itemDescription,
            url: URL(string: url) ?? URL(string: "about:blank") ?? URL(fileURLWithPath: "/"),
            imageURL: imageURL.flatMap { URL(string: $0) },
            source: source,
            category: category,
            pubDate: pubDate,
            contentHTML: contentHTML
        )
        item.hasQualityImage = item.imageURL != nil
        return item
    }
}
