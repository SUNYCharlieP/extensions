import Foundation

struct FeedItem: Identifiable, Equatable {
    var id: String { url.absoluteString }

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.url == rhs.url
    }
    let title: String
    let itemDescription: String
    let url: URL
    var imageURL: URL?
    let source: String
    var category: String
    let pubDate: Date
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
            if str.hasPrefix("http") {
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
        // General Tech
        RSSFeed(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: "General Tech"),
        RSSFeed(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: "General Tech"),
        RSSFeed(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: "General Tech"),
        RSSFeed(name: "Wired", url: "https://www.wired.com/feed/rss", category: "General Tech"),
        RSSFeed(name: "Engadget", url: "https://www.engadget.com/rss.xml", category: "General Tech"),
        RSSFeed(name: "The Register", url: "https://www.theregister.com/headlines.atom", category: "General Tech"),
        // Science & Research
        RSSFeed(name: "MIT Technology Review", url: "https://www.technologyreview.com/feed/", category: "Science"),
        // Hacker News
        RSSFeed(name: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Hacker News"),
        // Security
        RSSFeed(name: "Krebs on Security", url: "https://krebsonsecurity.com/feed/", category: "Security"),
        // Tech Videos (YouTube RSS)
        RSSFeed(name: "MKBHD", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCBJycsmduvYEL83R_U4JriQ", category: "Videos", isVideo: true),
        RSSFeed(name: "Linus Tech Tips", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCXuqSBlHAE6Xw-yeJA0Tunw", category: "Videos", isVideo: true),
        RSSFeed(name: "The Verge (Video)", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCddiUEpeqJcYeBxX1IVBKvQ", category: "Videos", isVideo: true),
        RSSFeed(name: "Fireship", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA", category: "Videos", isVideo: true),
        RSSFeed(name: "Dave Lee", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCVYamHKEnwaVx3zv4BNiRDA", category: "Videos", isVideo: true),
        // News-focused tech video channels
        RSSFeed(name: "CNET", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCXFNrRMSNPH4F1Ib5GNjSMA", category: "Videos", isVideo: true),
        RSSFeed(name: "Wired (Video)", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCftwRNsjfRo08xYE31tkiyw", category: "Videos", isVideo: true),
        RSSFeed(name: "Wall Street Journal Tech", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCK7tptUDHh-RYDsdxO1-5QQ", category: "Videos", isVideo: true),
        RSSFeed(name: "Bloomberg Technology", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCrM7B7SL_g1edFOnmj-SDKg", category: "Videos", isVideo: true),
        RSSFeed(name: "CNBC TechCheck", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCvJJ_dzjViJCoLf5uKUTwoA", category: "Videos", isVideo: true),
        RSSFeed(name: "Tom's Guide", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC-yzLkKRIHKzMRiPCnqmMdA", category: "Videos", isVideo: true),
        RSSFeed(name: "Austin Evans", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCXGgrKt94gR6lmN4aN3mYTg", category: "Videos", isVideo: true),
        // Shorts — channels that primarily post short-form tech content
        RSSFeed(name: "TechLinked", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCeeFfhMcJa1kjtfZAGskOCA", category: "Shorts", isVideo: true, isShort: true),
        RSSFeed(name: "ShortCircuit", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCdBK94H6oZT2Q7l0-b0xmMg", category: "Shorts", isVideo: true, isShort: true),
        RSSFeed(name: "JerryRigEverything", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCWFKCr40YwOZQx8FHU_ZqqQ", category: "Shorts", isVideo: true, isShort: true),
        RSSFeed(name: "Mrwhosetheboss", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCMiJRAwDNSNzuYeN2uWa0pA", category: "Shorts", isVideo: true, isShort: true),
        RSSFeed(name: "Unbox Therapy", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsTcErHg8oDvUnTzoqsYeNw", category: "Shorts", isVideo: true, isShort: true),
        RSSFeed(name: "iJustine", url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCey_c7U86mJGz1VJWH5CYPA", category: "Shorts", isVideo: true, isShort: true),
    ]
}
