import Foundation

class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "arca_bookmarks"
    /// Serial queue prevents out-of-order UserDefaults writes.
    private let persistQueue = DispatchQueue(label: "com.arca.bookmarks.persist")

    @Published var bookmarkedURLs: Set<String>

    private init() {
        bookmarkedURLs = Set(defaults.stringArray(forKey: bookmarkKey) ?? [])
    }

    func isBookmarked(_ item: FeedItem) -> Bool {
        bookmarkedURLs.contains(item.url.absoluteString)
    }

    func toggle(_ item: FeedItem) {
        let url = item.url.absoluteString
        if bookmarkedURLs.contains(url) {
            bookmarkedURLs.remove(url)
        } else {
            bookmarkedURLs.insert(url)
        }
        let snapshot = Array(bookmarkedURLs)
        let key = bookmarkKey
        persistQueue.async { [weak self] in
            guard self != nil else { return }
            UserDefaults.standard.set(snapshot, forKey: key)
        }
    }

    /// Merge bookmarks from cloud sync without bypassing persistence.
    func mergeFromCloud(_ urls: Set<String>) {
        let merged = bookmarkedURLs.union(urls)
        guard merged != bookmarkedURLs else { return }
        bookmarkedURLs = merged
        defaults.set(Array(bookmarkedURLs), forKey: bookmarkKey)
    }
}
