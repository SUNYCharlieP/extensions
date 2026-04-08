import Foundation

class ReadStateManager: ObservableObject {
    static let shared = ReadStateManager()

    private let defaults = UserDefaults.standard
    private let readKey = "arca_read_urls"

    @Published var readURLs: Set<String>
    /// Ordered list so we can evict oldest-first (FIFO).
    private var readOrder: [String]

    private init() {
        let stored = defaults.stringArray(forKey: readKey) ?? []
        readURLs = Set(stored)
        readOrder = stored
    }

    func isRead(_ item: FeedItem) -> Bool {
        readURLs.contains(item.url.absoluteString)
    }

    func markRead(_ item: FeedItem) {
        let url = item.url.absoluteString
        guard !readURLs.contains(url) else { return }
        // Cap at 2000 entries — evict oldest first
        while readURLs.count >= 2000, let oldest = readOrder.first {
            readOrder.removeFirst()
            readURLs.remove(oldest)
        }
        readURLs.insert(url)
        readOrder.append(url)
        defaults.set(readOrder, forKey: readKey)
    }

    var unreadCount: Int {
        // This is a rough count — caller must compare against their item list
        0
    }

    func unreadCount(in items: [FeedItem]) -> Int {
        items.filter { !isRead($0) }.count
    }
}
