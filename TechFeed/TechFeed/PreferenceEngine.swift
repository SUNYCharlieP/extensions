import Foundation

class PreferenceEngine {
    static let shared = PreferenceEngine()

    private let defaults = UserDefaults.standard
    private let sourceKey = "pref_source_counts"
    private let keywordKey = "pref_keyword_counts"
    private let totalTapsKey = "pref_total_taps"
    private let likedKey = "pref_liked_urls"

    private var cachedSources: [String: Int]
    private var cachedKeywords: [String: Int]
    private var cachedTotalTaps: Int
    private var cachedLikedURLs: Set<String>

    private let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "shall", "can", "need", "dare", "ought",
        "and", "but", "or", "nor", "not", "so", "yet", "both", "either",
        "neither", "each", "every", "all", "any", "few", "more", "most",
        "other", "some", "such", "no", "only", "own", "same", "than",
        "too", "very", "just", "because", "as", "until", "while", "of",
        "at", "by", "for", "with", "about", "against", "between", "through",
        "during", "before", "after", "above", "below", "to", "from", "up",
        "down", "in", "out", "on", "off", "over", "under", "again", "further",
        "then", "once", "here", "there", "when", "where", "why", "how",
        "what", "which", "who", "whom", "this", "that", "these", "those",
        "i", "me", "my", "myself", "we", "our", "ours", "you", "your",
        "he", "him", "his", "she", "her", "it", "its", "they", "them",
        "their", "new", "says", "now", "get", "got", "into", "also",
        "comments", "one", "two", "first", "like", "make", "many",
    ]

    private init() {
        cachedSources = defaults.dictionary(forKey: sourceKey) as? [String: Int] ?? [:]
        cachedKeywords = defaults.dictionary(forKey: keywordKey) as? [String: Int] ?? [:]
        cachedTotalTaps = defaults.integer(forKey: totalTapsKey)
        cachedLikedURLs = Set(defaults.stringArray(forKey: likedKey) ?? [])
    }

    func recordTap(on item: FeedItem) {
        cachedTotalTaps += 1
        cachedSources[item.source, default: 0] += 1
        for keyword in extractKeywords(from: item.title) {
            cachedKeywords[keyword, default: 0] += 1
        }
        persistAsync()
    }

    func recordLike(on item: FeedItem) {
        let url = item.url.absoluteString
        guard !cachedLikedURLs.contains(url) else { return }
        cachedLikedURLs.insert(url)
        // 3x weight — a like is a much stronger signal than a tap
        cachedSources[item.source, default: 0] += 3
        for keyword in extractKeywords(from: item.title) {
            cachedKeywords[keyword, default: 0] += 3
        }
        cachedTotalTaps += 3
        persistAsync()
    }

    func removeLike(on item: FeedItem) {
        let url = item.url.absoluteString
        guard cachedLikedURLs.contains(url) else { return }
        cachedLikedURLs.remove(url)
        // Reverse the 3x weight boost from recordLike
        cachedSources[item.source] = max(0, (cachedSources[item.source] ?? 0) - 3)
        for keyword in extractKeywords(from: item.title) {
            cachedKeywords[keyword] = max(0, (cachedKeywords[keyword] ?? 0) - 3)
        }
        cachedTotalTaps = max(0, cachedTotalTaps - 3)
        persistAsync()
    }

    func isLiked(_ item: FeedItem) -> Bool {
        cachedLikedURLs.contains(item.url.absoluteString)
    }

    /// Returns 0–1 affinity for a source based on tap history. Used for dedup tie-breaking.
    func sourceAffinity(_ source: String) -> Double {
        guard let max = cachedSources.values.max(), max > 0 else { return 0 }
        return Double(cachedSources[source] ?? 0) / Double(max)
    }

    private func persistAsync() {
        let sources = cachedSources
        let keywords = cachedKeywords
        let taps = cachedTotalTaps
        let liked = Array(cachedLikedURLs)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.defaults.set(sources, forKey: self.sourceKey)
            self.defaults.set(keywords, forKey: self.keywordKey)
            self.defaults.set(taps, forKey: self.totalTapsKey)
            self.defaults.set(liked, forKey: self.likedKey)
        }
    }

    func scoreItems(_ items: [FeedItem]) -> [FeedItem] {
        guard cachedTotalTaps >= 3 else {
            return items.sorted { $0.pubDate > $1.pubDate }
        }

        let maxSourceCount = Double(cachedSources.values.max() ?? 1)
        let maxKeywordCount = Double(cachedKeywords.values.max() ?? 1)

        var scored = items.map { item -> FeedItem in
            var item = item

            let sourceScore = Double(cachedSources[item.source] ?? 0) / maxSourceCount

            let titleKeywords = extractKeywords(from: item.title)
            let keywordScore: Double
            if titleKeywords.isEmpty {
                keywordScore = 0
            } else {
                let totalRelevance = titleKeywords.reduce(0.0) { sum, kw in
                    sum + Double(cachedKeywords[kw] ?? 0) / maxKeywordCount
                }
                keywordScore = totalRelevance / Double(titleKeywords.count)
            }

            let age = Date().timeIntervalSince(item.pubDate)
            let recencyScore = max(0, 1.0 - age / (48 * 3600))

            let prefWeight = min(Double(cachedTotalTaps) / 30.0, 0.4)
            let recencyWeight = 1.0 - prefWeight

            item.preferenceScore = recencyWeight * recencyScore
                + prefWeight * (0.6 * sourceScore + 0.4 * keywordScore)

            return item
        }

        scored.sort {
            if abs($0.preferenceScore - $1.preferenceScore) < 0.001 {
                return $0.pubDate > $1.pubDate
            }
            return $0.preferenceScore > $1.preferenceScore
        }
        return scored
    }

    private func extractKeywords(from title: String) -> [String] {
        title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
