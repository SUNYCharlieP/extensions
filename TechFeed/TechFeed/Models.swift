import Foundation

struct FeedItem: Identifiable, Equatable {
    var id: String { url.absoluteString }

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.url == rhs.url &&
        lhs.title == rhs.title &&
        lhs.category == rhs.category &&
        lhs.imageURL == rhs.imageURL &&
        lhs.isTrending == rhs.isTrending &&
        lhs.hasQualityImage == rhs.hasQualityImage &&
        lhs.relatedArticles.map(\.id) == rhs.relatedArticles.map(\.id)
    }
    let title: String
    let itemDescription: String
    let url: URL
    var imageURL: URL?
    let source: String
    var category: String
    let pubDate: Date
    /// Full HTML content from content:encoded or description, for native reader.
    var contentHTML: String = ""
    var preferenceScore: Double = 0
    var isVideo: Bool = false
    var isShort: Bool = false
    /// Other sources covering the same story (populated by dedup grouping).
    var relatedArticles: [FeedItem] = []

    // ── Precomputed properties (set once during feed processing) ──
    var isTrending: Bool = false
    var readingTime: Int = 2
    var hasQualityImage: Bool = false

    /// Total number of sources covering this story (self + related).
    var sourceCount: Int { 1 + relatedArticles.count }

    /// Recompute cached properties. Called once after dedup/scoring, not on every access.
    mutating func computeDerivedProperties() {
        // Reading time
        let words = itemDescription.split(separator: " ").count
        let minutes = max(1, words / 200)
        readingTime = words < 30 ? 2 : minutes

        // Quality image check
        if let imgURL = imageURL {
            let str = imgURL.absoluteString.lowercased()
            if str.hasPrefix("http") || str.hasPrefix("//") {
                hasQualityImage = !Self.junkPatterns.contains(where: { str.contains($0) })
            }
        }

        // Trending
        if relatedArticles.count >= 2 {
            let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)
            let hasRecentCoverage = relatedArticles.contains { $0.pubDate > threeHoursAgo }
            isTrending = hasRecentCoverage || pubDate > threeHoursAgo
        }
    }

    private static let junkPatterns = [
        "logo", "icon", "avatar", "favicon", "pixel", "1x1",
        "tracking", "spacer", "blank", ".svg", ".gif", "data:",
        "gravatar", "sprite", "badge", "emoji", "button",
        "placeholder", "default-image", "no-image", "noimage"
    ]
}

// MARK: - Relative Time Formatting

extension Date {
    /// "2m ago", "3h ago", "1d ago" — never shows seconds.
    var relativeString: String {
        let seconds = Int(Date().timeIntervalSince(self))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        return "\(weeks)w ago"
    }
}

struct RSSFeed {
    let name: String
    let url: String
    let category: String
    var isVideo: Bool = false
    var isShort: Bool = false

    static let allFeeds: [RSSFeed] = [
        // Apple
        RSSFeed(name: "9to5Mac", url: "https://9to5mac.com/feed/", category: "Apple"),
        RSSFeed(name: "MacRumors", url: "https://feeds.macrumors.com/MacRumors-All", category: "Apple"),
        RSSFeed(name: "AppleInsider", url: "https://appleinsider.com/rss/news/", category: "Apple"),
        // General Tech
        RSSFeed(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: "General Tech"),
        RSSFeed(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: "General Tech"),
        RSSFeed(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: "General Tech"),
        RSSFeed(name: "Wired", url: "https://www.wired.com/feed/rss", category: "General Tech"),
        RSSFeed(name: "Engadget", url: "https://www.engadget.com/rss.xml", category: "General Tech"),
        RSSFeed(name: "The Register", url: "https://www.theregister.com/headlines.atom", category: "General Tech"),
        RSSFeed(name: "Techmeme", url: "https://www.techmeme.com/feed.xml", category: "General Tech"),
        RSSFeed(name: "404 Media", url: "https://www.404media.co/rss/", category: "General Tech"),
        RSSFeed(name: "ZDNET", url: "https://www.zdnet.com/rss.xml", category: "General Tech"),
        RSSFeed(name: "Phoronix", url: "https://www.phoronix.com/rss.php", category: "General Tech"),
        RSSFeed(name: "Fortune", url: "https://fortune.com/feed/", category: "General Tech"),
        RSSFeed(name: "TLDR", url: "https://tldr.tech/api/rss/tech", category: "General Tech"),
        RSSFeed(name: "Reuters Tech", url: "https://news.google.com/rss/search?q=reuters+technology&hl=en-US&gl=US&ceid=US:en", category: "General Tech"),
        RSSFeed(name: "TechSpot", url: "https://www.techspot.com/backend/rss/rss.xml", category: "General Tech"),
        // Reviews
        RSSFeed(name: "PCMag", url: "https://www.pcmag.com/rss", category: "Reviews"),
        RSSFeed(name: "CNET", url: "https://www.cnet.com/rss/news/", category: "Reviews"),
        RSSFeed(name: "Tom's Hardware", url: "https://www.tomshardware.com/feeds/all", category: "Reviews"),
        // Android (mixed into General Tech)
        RSSFeed(name: "Android Authority", url: "https://www.androidauthority.com/feed/", category: "General Tech"),
        RSSFeed(name: "9to5Google", url: "https://9to5google.com/feed/", category: "General Tech"),
        // Science & Research
        RSSFeed(name: "MIT Technology Review", url: "https://www.technologyreview.com/feed/", category: "Science"),
        // Hacker News
        RSSFeed(name: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Hacker News"),
        // Security
        RSSFeed(name: "Krebs on Security", url: "https://krebsonsecurity.com/feed/", category: "Security"),
    ]
}
