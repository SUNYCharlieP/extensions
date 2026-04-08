import Foundation

class SourceManager: ObservableObject {
    static let shared = SourceManager()

    private let defaults = UserDefaults.standard
    private let disabledKey = "arca_disabled_sources"
    private let customKey = "arca_custom_feeds"
    private let hasOnboardedKey = "arca_has_onboarded"

    @Published var disabledSources: Set<String>
    @Published var customFeeds: [RSSFeed]
    @Published var hasOnboarded: Bool

    private init() {
        disabledSources = Set(defaults.stringArray(forKey: disabledKey) ?? [])
        hasOnboarded = defaults.bool(forKey: hasOnboardedKey)

        if let data = defaults.data(forKey: customKey),
           let decoded = try? JSONDecoder().decode([CodableFeed].self, from: data) {
            customFeeds = decoded.map { RSSFeed(name: $0.name, url: $0.url, category: $0.category) }
        } else {
            customFeeds = []
        }
    }

    var enabledFeeds: [RSSFeed] {
        let builtIn = RSSFeed.allFeeds.filter { !disabledSources.contains($0.name) }
        return builtIn + customFeeds
    }

    func isEnabled(_ source: String) -> Bool {
        !disabledSources.contains(source)
    }

    func toggle(_ source: String) {
        if disabledSources.contains(source) {
            disabledSources.remove(source)
        } else {
            disabledSources.insert(source)
        }
        defaults.set(Array(disabledSources), forKey: disabledKey)
    }

    func addCustomFeed(name: String, url: String, category: String) {
        let feed = RSSFeed(name: name, url: url, category: category)
        customFeeds.append(feed)
        persistCustomFeeds()
    }

    func removeCustomFeed(at index: Int) {
        guard index < customFeeds.count else { return }
        customFeeds.remove(at: index)
        persistCustomFeeds()
    }

    func completeOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: hasOnboardedKey)
    }

    private func persistCustomFeeds() {
        let codable = customFeeds.map { CodableFeed(name: $0.name, url: $0.url, category: $0.category) }
        if let data = try? JSONEncoder().encode(codable) {
            defaults.set(data, forKey: customKey)
        }
    }
}

private struct CodableFeed: Codable {
    let name: String
    let url: String
    let category: String
}
