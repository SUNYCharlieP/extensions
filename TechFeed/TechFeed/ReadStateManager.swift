import Foundation

class ReadStateManager: ObservableObject {
    static let shared = ReadStateManager()

    private let defaults = UserDefaults.standard
    private let readKey = "arca_read_urls"

    @Published var readURLs: Set<String>

    private init() {
        readURLs = Set(defaults.stringArray(forKey: readKey) ?? [])
    }

    func isRead(_ item: FeedItem) -> Bool {
        readURLs.contains(item.url.absoluteString)
    }

    func markRead(_ item: FeedItem) {
        let url = item.url.absoluteString
        guard !readURLs.contains(url) else { return }
        readURLs.insert(url)
        defaults.set(Array(readURLs), forKey: readKey)
    }

    var unreadCount: Int {
        // This is a rough count — caller must compare against their item list
        0
    }

    func unreadCount(in items: [FeedItem]) -> Int {
        items.filter { !isRead($0) }.count
    }
}
