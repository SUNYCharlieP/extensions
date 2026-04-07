import Foundation

struct FeedItem: Identifiable {
    let id = UUID()
    let title: String
    let itemDescription: String
    let url: URL
    var imageURL: URL?
    let source: String
    let pubDate: Date
    var preferenceScore: Double = 0
}

struct RSSFeed {
    let name: String
    let url: String
    let category: String

    static let allFeeds: [RSSFeed] = [
        RSSFeed(name: "The Verge", url: "https://www.theverge.com/rss/index.xml", category: "General Tech"),
        RSSFeed(name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", category: "General Tech"),
        RSSFeed(name: "9to5Mac", url: "https://9to5mac.com/feed/", category: "Apple"),
        RSSFeed(name: "MacRumors", url: "https://feeds.macrumors.com/MacRumors-All", category: "Apple"),
        RSSFeed(name: "TechCrunch", url: "https://techcrunch.com/feed/", category: "General Tech"),
        RSSFeed(name: "MIT Technology Review", url: "https://www.technologyreview.com/feed/", category: "Science"),
        RSSFeed(name: "Hacker News", url: "https://news.ycombinator.com/rss", category: "Hacker News"),
        RSSFeed(name: "Krebs on Security", url: "https://krebsonsecurity.com/feed/", category: "Security"),
    ]
}
