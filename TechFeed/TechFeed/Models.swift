import Foundation

struct FeedItem: Identifiable {
    let id = UUID()
    let title: String
    let itemDescription: String
    let url: URL
    var imageURL: URL?
    let source: String
    var category: String
    let pubDate: Date
    var preferenceScore: Double = 0
    var isVideo: Bool = false
    /// Other sources covering the same story (populated by dedup grouping).
    var relatedArticles: [FeedItem] = []

    /// Whether this story is trending — 3+ sources covering the same topic
    /// within a 3-hour window signals breaking/hot news.
    var isTrending: Bool {
        guard relatedArticles.count >= 2 else { return false }
        let threeHoursAgo = Date().addingTimeInterval(-3 * 3600)
        // At least one related article must be recent
        let hasRecentCoverage = relatedArticles.contains { $0.pubDate > threeHoursAgo }
        return hasRecentCoverage || pubDate > threeHoursAgo
    }

    /// Total number of sources covering this story (self + related).
    var sourceCount: Int { 1 + relatedArticles.count }

    /// Estimated reading time in minutes based on description word count.
    /// Falls back to 2 min when description is too short to estimate.
    var readingTime: Int {
        let words = itemDescription.split(separator: " ").count
        let minutes = max(1, words / 200) // ~200 wpm reading speed
        return words < 30 ? 2 : minutes
    }

    /// Whether the image URL points to a real content image suitable for
    /// prominent display (hero card, featured grid). Filters out logos,
    /// icons, tracking pixels, SVGs, GIFs, and other junk.
    var hasQualityImage: Bool {
        guard let url = imageURL else { return false }
        let str = url.absoluteString.lowercased()
        guard str.hasPrefix("http") else { return false }
        let junk = ["logo", "icon", "avatar", "favicon", "pixel", "1x1",
                     "tracking", "spacer", "blank", ".svg", ".gif", "data:",
                     "gravatar", "sprite", "badge", "emoji", "button",
                     "placeholder", "default-image", "no-image", "noimage"]
        return !junk.contains(where: { str.contains($0) })
    }
}

struct RSSFeed {
    let name: String
    let url: String
    let category: String
    var isVideo: Bool = false

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
    ]
}
