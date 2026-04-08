import Foundation

class BookmarkManager: ObservableObject {
    static let shared = BookmarkManager()

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "arca_bookmarks"

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
        defaults.set(Array(bookmarkedURLs), forKey: bookmarkKey)
    }

    /// Merge bookmarks from cloud sync without bypassing persistence.
    func mergeFromCloud(_ urls: Set<String>) {
        let merged = bookmarkedURLs.union(urls)
        guard merged != bookmarkedURLs else { return }
        bookmarkedURLs = merged
        defaults.set(Array(bookmarkedURLs), forKey: bookmarkKey)
    }
}
