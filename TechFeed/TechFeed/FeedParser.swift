import Foundation

class FeedParser: ObservableObject {
    @Published var items: [FeedItem] = []
    @Published var isLoading: Bool = false

    private let lock = NSLock()
    private let preferences = PreferenceEngine.shared
    /// Continuations waiting for the current fetch to finish.
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    /// When true, a new fetch will start after the current one finishes.
    private var needsRefresh = false
    private let ogImageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    func fetchAllFeeds() {
        guard !isLoading else {
            needsRefresh = true
            return
        }
        isLoading = true
        startFetch(continuation: nil)
    }

    /// Push top stories to the widget via shared UserDefaults.
    private static func updateWidgetData(_ items: [FeedItem]) {
        struct WidgetStory: Codable {
            let title: String
            let source: String
            let isTrending: Bool
        }
        let stories = items.prefix(5).map { WidgetStory(title: $0.title, source: $0.source, isTrending: $0.isTrending) }
        if let data = try? JSONEncoder().encode(stories) {
            UserDefaults(suiteName: "group.com.arca.techfeed")?.set(data, forKey: "widget_stories")
        }
    }

    func fetchAllFeedsAsync() async {
        await withCheckedContinuation { continuation in
            // Ensure all state access is on main thread
            let work = { [self] in
                guard !self.isLoading else {
                    self.needsRefresh = true
                    self.pendingContinuations.append(continuation)
                    return
                }
                self.isLoading = true
                self.startFetch(continuation: continuation)
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.async { work() } }
        }
    }

    private func startFetch(continuation: CheckedContinuation<Void, Never>?) {
        var collectedItems: [FeedItem] = []
        let group = DispatchGroup()

        for feed in SourceManager.shared.enabledFeeds {
            guard let url = URL(string: feed.url) else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
                defer { group.leave() }
                guard let self = self, let data = data, error == nil else { return }

                let delegate = FeedXMLParserDelegate(sourceName: feed.name, category: feed.category, isVideo: feed.isVideo, isShort: feed.isShort)
                let parser = XMLParser(data: data)
                parser.delegate = delegate
                parser.parse()

                self.lock.lock()
                collectedItems.append(contentsOf: delegate.items)
                self.lock.unlock()
            }.resume()
        }

        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else {
                continuation?.resume()
                return
            }
            self.lock.lock()
            let snapshot = collectedItems
            self.lock.unlock()
            var filtered = snapshot.filter { !Self.isPromo($0) }
            Self.enrichVergeArticles(&filtered)
            let categorized = Self.categorize(filtered)
            let deduped = Self.deduplicate(categorized, preferences: self.preferences)
            let scored = self.preferences.scoreItems(deduped)
            let diverse = Self.diversify(scored)
            var final = Self.promoteHero(diverse)
            for i in final.indices { final[i].computeDerivedProperties() }

            // Widget data & notifications can be prepared off main thread
            Self.updateWidgetData(final)
            NotificationManager.shared.checkForBreakingStories(final)

            DispatchQueue.main.async {
                self.items = final
                self.isLoading = false
                self.fetchMissingImages()
                // Snapshot bookmarked URLs on main thread, dispatch I/O to background
                let bookmarkedSnapshot = BookmarkManager.shared.bookmarkedURLs
                DispatchQueue.global(qos: .utility).async {
                    OfflineCacheManager.shared.cacheBookmarkedArticles(from: final, bookmarkedURLs: bookmarkedSnapshot)
                    OfflineCacheManager.shared.pruneOldCache()
                }
                continuation?.resume()
                for pending in self.pendingContinuations { pending.resume() }
                self.pendingContinuations.removeAll()
                if self.needsRefresh {
                    self.needsRefresh = false
                    self.fetchAllFeeds()
                }
            }
        }
    }

    private func fetchMissingImages() {
        let missing = items.filter { $0.imageURL == nil }
        guard !missing.isEmpty else { return }

        // Limit to 10 requests to avoid memory pressure
        for item in missing.prefix(10) {
            let itemID = item.id
            let articleURL = item.url
            var request = URLRequest(url: articleURL)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

            ogImageSession.dataTask(with: request) { [weak self] data, _, _ in
                guard let data = data,
                      let fullHTML = String(data: data, encoding: .utf8) else { return }
                let html = String(fullHTML.prefix(50_000))

                guard let imageStr = Self.extractBestImage(from: html, pageURL: articleURL),
                      let imageURL = URL(string: imageStr) else { return }

                DispatchQueue.main.async {
                    guard let self = self,
                          let idx = self.items.firstIndex(where: { $0.id == itemID }) else { return }
                    self.items[idx].imageURL = imageURL
                    let str = imageURL.absoluteString.lowercased()
                    self.items[idx].hasQualityImage = (str.hasPrefix("http") || str.hasPrefix("//")) && !FeedItem.junkPatterns.contains(where: { str.contains($0) })
                }
            }.resume()
        }
    }

    /// Cascading image extraction — tries every method before giving up.
    private static func extractBestImage(from html: String, pageURL: URL) -> String? {
        // 1. og:image / twitter:image (most reliable)
        if let meta = extractMetaImage(from: html) { return meta }

        // 2. <link rel="image_src"> or itemprop="image"
        if let link = extractLinkImage(from: html) { return link }

        // 3. First meaningful <img> in page body (skip icons, avatars, etc.)
        if let img = extractContentImage(from: html, baseURL: pageURL) { return img }

        return nil
    }


    // MARK: - Deduplication

    /// Words that carry no topical signal — filtered before comparing titles.
    private static let dedupStopWords: Set<String> = [
        "the", "for", "and", "but", "not", "you", "all", "can", "her", "was",
        "one", "our", "out", "are", "has", "his", "how", "its", "may", "new",
        "now", "old", "see", "way", "who", "did", "get", "got", "had", "him",
        "let", "say", "she", "too", "use", "with", "this", "that", "from",
        "have", "been", "will", "more", "when", "what", "some", "than", "them",
        "then", "into", "just", "over", "also", "back", "after", "could", "would",
        "about", "which", "their", "there", "first", "being", "where", "those",
        "still", "every", "should", "while", "here", "says", "said", "like",
        "make", "made", "most", "much", "many", "your", "does", "best", "very",
        "other", "show", "shows", "report", "reports", "according", "update",
        "look", "looks", "why", "how", "big", "top", "via",
    ]

    private static func significantWords(from title: String) -> Set<String> {
        let words = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !dedupStopWords.contains($0) }
        return Set(words)
    }

    private static func deduplicate(_ items: [FeedItem], preferences: PreferenceEngine) -> [FeedItem] {
        guard !items.isEmpty else { return items }

        // First pass: remove exact URL duplicates (e.g., Techmeme rewriting to a source already in the feed)
        var seenURLs = Set<String>()
        let uniqueItems = items.filter { item in
            let key = item.url.absoluteString
            guard !seenURLs.contains(key) else { return false }
            seenURLs.insert(key)
            return true
        }
        let items = uniqueItems

        var result: [FeedItem] = []
        var usedIndices = Set<Int>()

        let keywordSets = items.map { significantWords(from: $0.title) }

        for i in 0..<items.count {
            guard !usedIndices.contains(i) else { continue }

            var group = [i]
            let wordsA = keywordSets[i]
            guard wordsA.count >= 2 else {
                result.append(items[i])
                usedIndices.insert(i)
                continue
            }

            for j in (i + 1)..<items.count {
                guard !usedIndices.contains(j) else { continue }
                let wordsB = keywordSets[j]
                guard wordsB.count >= 2 else { continue }

                let shared = wordsA.intersection(wordsB)
                let union = wordsA.union(wordsB)
                guard !union.isEmpty else { continue }
                let jaccard = Double(shared.count) / Double(union.count)

                if jaccard >= 0.4 || shared.count >= 3 {
                    group.append(j)
                    usedIndices.insert(j)
                }
            }

            // Pick the best: preferred source → has image → newest
            guard let bestIdx = group.max(by: { a, b in
                let itemA = items[a]
                let itemB = items[b]
                let scoreA = preferences.sourceAffinity(itemA.source) + (itemA.imageURL != nil ? 0.5 : 0)
                let scoreB = preferences.sourceAffinity(itemB.source) + (itemB.imageURL != nil ? 0.5 : 0)
                if abs(scoreA - scoreB) > 0.01 { return scoreA < scoreB }
                return itemA.pubDate < itemB.pubDate
            }) else { continue }

            // Attach other sources as "More Coverage" on the winning item
            var bestItem = items[bestIdx]
            let related = group.filter { $0 != bestIdx }.map { items[$0] }
            if !related.isEmpty {
                bestItem.relatedArticles = related
            }

            result.append(bestItem)
            // Mark all group members (including i) as used
            for idx in group { usedIndices.insert(idx) }
        }

        return result
    }

    // MARK: - Hero Promotion

    /// Picks the best hero candidate and moves it to index 0.
    /// Hero must be: < 6 hours old, have an image, and rotates on a 2-hour cycle.
    private static func promoteHero(_ items: [FeedItem]) -> [FeedItem] {
        guard items.count > 1 else { return items }

        let sixHoursAgo = Date().addingTimeInterval(-6 * 3600)
        let candidates = items.enumerated().filter { (_, item) in
            item.imageURL != nil && item.pubDate > sixHoursAgo
        }

        guard !candidates.isEmpty else { return items }

        // Rotate hero every 2 hours using a time-based seed
        let twoHourSlot = Int(Date().timeIntervalSince1970) / 7200
        let heroIndex = candidates[twoHourSlot % candidates.count].offset

        guard heroIndex != 0, heroIndex < items.count else { return items }

        var reordered = items
        let hero = reordered.remove(at: heroIndex)
        reordered.insert(hero, at: 0)
        return reordered
    }

    // MARK: - Source Diversity

    /// Reorders scored items so no single source dominates the feed.
    /// Rules:
    ///  - No more than 2 consecutive items from the same source.
    ///  - Top 10 visual slots (hero + featured + first "more stories") must include
    ///    at least 4 distinct sources.
    ///  - Uses a round-robin pull from per-source queues, ordered by best score,
    ///    so high-quality articles still surface first for each source.
    private static func diversify(_ items: [FeedItem]) -> [FeedItem] {
        guard items.count > 3 else { return items }

        // Group items by source, preserving score order within each group
        var buckets: [String: [FeedItem]] = [:]
        for item in items {
            buckets[item.source, default: []].append(item)
        }

        // Order sources by their top item's score (descending)
        let sourceOrder = buckets.keys.sorted { a, b in
            let scoreA = buckets[a]!.first?.preferenceScore ?? 0
            let scoreB = buckets[b]!.first?.preferenceScore ?? 0
            if abs(scoreA - scoreB) < 0.001 {
                // Tie-break: rotate order hourly using a stable hash (not Swift's randomized hashValue)
                let slot = Int(Date().timeIntervalSince1970) / 3600
                func stableHash(_ s: String) -> Int {
                    s.utf8.reduce(5381) { ($0 &<< 5) &+ $0 &+ Int($1) }
                }
                return (stableHash(a) ^ slot) < (stableHash(b) ^ slot)
            }
            return scoreA > scoreB
        }

        var result: [FeedItem] = []
        var sourceQueues: [String: [FeedItem]] = buckets
        let totalCount = items.count

        while result.count < totalCount {
            var addedThisRound = false
            var skippedSources: [(String, [FeedItem])] = []

            for source in sourceOrder {
                guard var queue = sourceQueues[source], !queue.isEmpty else { continue }

                // Check consecutive limit: skip if last 2 items are from this source
                let tail = result.suffix(2)
                if tail.count == 2 && tail.allSatisfy({ $0.source == source }) {
                    skippedSources.append((source, queue))
                    continue
                }
                // Prefer to avoid 3+ consecutive items from the same category
                if let next = queue.first {
                    let catTail = result.suffix(2)
                    if catTail.count == 2 && catTail.allSatisfy({ $0.category == next.category }) {
                        skippedSources.append((source, queue))
                        continue
                    }
                }

                result.append(queue.removeFirst())
                sourceQueues[source] = queue
                addedThisRound = true
            }

            // If no source passed both checks, relax the category check and add from skipped
            if !addedThisRound && !skippedSources.isEmpty {
                for (source, var queue) in skippedSources {
                    guard !queue.isEmpty else { continue }
                    // Still enforce source-consecutive limit, but allow category runs
                    let tail = result.suffix(2)
                    if tail.count == 2 && tail.allSatisfy({ $0.source == source }) {
                        continue
                    }
                    result.append(queue.removeFirst())
                    sourceQueues[source] = queue
                    addedThisRound = true
                    break
                }
            }

            // Final safety: drain remaining if truly stuck
            if !addedThisRound {
                for source in sourceOrder {
                    if let queue = sourceQueues[source], !queue.isEmpty {
                        result.append(contentsOf: queue)
                        sourceQueues[source] = []
                    }
                }
                break
            }
        }

        return result
    }

    // MARK: - Keyword-Based Categorization

    /// Per-article keyword categorization — overrides source-level category
    /// when the content clearly belongs elsewhere. More specific categories
    /// win over general ones.
    private static let categoryKeywords: [(category: String, keywords: [String])] = [
        // Most specific first — order matters for tie-breaking
        ("Security", [
            "hack", "hacked", "hacker", "breach", "malware", "ransomware",
            "vulnerability", "exploit", "phishing", "cybersecurity", "cyber",
            "zero-day", "zero day", "cve-", "infosec", "botnet", "ddos",
            "trojan", "spyware", "encryption", "data leak", "data breach",
            "security flaw", "password", "credential", "authentication",
        ]),
        ("Apple", [
            "iphone", "ipad", "macbook", "imac", "mac pro", "mac mini",
            "mac studio", "apple watch", "watchos", "airpods", "airpod",
            "apple tv", "homepod", "vision pro", "visionos", "ios ",
            "ios26", "ios 26", "ipados", "macos", "carplay", "siri",
            "apple intelligence", "apple silicon", "m1 ", "m2 ", "m3 ",
            "m4 ", "m5 ", "a17", "a18", "swift ui", "swiftui", "xcode",
            "app store", "apple arcade", "apple music", "icloud",
            "9to5mac", "macrumors", "wwdc", "apple event",
        ]),
        ("Science", [
            "research", "study finds", "scientists", "researchers",
            "climate", "quantum", "nasa", "space", "physics", "biology",
            "genome", "crispr", "fusion", "neuroscience", "ai safety",
            "machine learning", "neural network", "deep learning",
            "laboratory", "experiment", "peer-reviewed", "journal",
            "artemis", "mars", "satellite", "telescope",
        ]),
        ("Hacker News", [
            // HN keeps its source-based category — no keyword override needed
        ]),
    ]

    /// Non-Apple subjects — if the TITLE is primarily about one of these,
    /// don't let a stray "iOS" in the description pull it into Apple.
    private static let nonAppleSubjects: [String] = [
        "google", "gemini", "android", "pixel", "chrome os", "chromebook",
        "samsung", "galaxy", "microsoft", "windows", "copilot", "bing",
        "meta ", "instagram", "whatsapp", "threads app",
        "amazon", "alexa", "kindle", "nvidia", "openai", "chatgpt",
        "tiktok", "snapchat", "spotify", "tesla", "spacex",
    ]

    /// Reclassify articles based on title + description keywords.
    /// Title is weighted more heavily — if the title is clearly about a
    /// non-Apple subject, the article won't be pulled into Apple even if
    /// the description mentions iOS/iPhone.
    private static func categorize(_ items: [FeedItem]) -> [FeedItem] {
        return items.map { item in
            // HN, Reviews, and Android items always keep their source category
            if item.source == "Hacker News" { return item }
            if item.category == "Reviews" || item.isVideo { return item }

            var mutItem = item
            let title = item.title.lowercased()
            let text = (item.title + " " + item.itemDescription).lowercased()

            // Check if title is primarily about a non-Apple company
            let titleIsNonApple = nonAppleSubjects.contains(where: { title.contains($0) })

            for (category, keywords) in categoryKeywords {
                guard !keywords.isEmpty else { continue }

                // Block Apple category if title subject is clearly non-Apple
                if category == "Apple" && titleIsNonApple { continue }

                if keywords.contains(where: { text.contains($0) }) {
                    mutItem.category = category
                    break
                }
            }

            return mutItem
        }
    }

    private static let promoPatterns: [String] = [
        "promo code", "coupon", "% off", "$ off", "discount code",
        "deal alert", "best deals", "save up to", "sale:", "days left to save",
        "affiliate", "sponsored", "shop now", "buy now", "limited time offer",
        "price drop", "lowest price", "black friday", "cyber monday",
        "gift guide", "buying guide",
        // Filter deal roundup / freebie posts (low-quality aggregation)
        "deals and freebies", "app deals", "freebies:", "today's deals",
        "best prices", "deals today", "deals roundup", "deals of the week",
        "deals for", "deals this week",
    ]

    private static func isPromo(_ item: FeedItem) -> Bool {
        let title = item.title.lowercased()
        let desc = item.itemDescription.lowercased()
        return promoPatterns.contains { pattern in
            title.contains(pattern) || desc.contains(pattern)
        }
    }

    // MARK: - Verge Article Enrichment

    /// For Verge articles with thin RSS content, attempt extraction.
    /// Successful extractions (200+ words) replace contentHTML.
    /// Failed extractions mark the item as subscriber-only.
    private static func enrichVergeArticles(_ items: inout [FeedItem]) {
        // Identify thin Verge articles and snapshot their URLs for async work
        var targets: [(index: Int, url: URL)] = []
        for i in items.indices {
            let source = items[i].source.lowercased()
            let host = items[i].url.host?.lowercased() ?? ""
            let isVerge = source.contains("the verge") || source.contains("theverge") || host.contains("theverge.com")
            guard isVerge else { continue }
            let wordCount = items[i].contentHTML.strippingHTMLTags()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ").count
            NSLog("[EnrichVerge] Verge article: %@ source: %@ host: %@ words: %d", items[i].url.absoluteString, items[i].source, host, wordCount)
            if wordCount < 300 {
                targets.append((index: i, url: items[i].url))
            }
        }
        NSLog("[EnrichVerge] Found %d thin Verge articles (checked %d total items)", targets.count, items.count)
        guard !targets.isEmpty else { return }

        // Bridge async extractions into synchronous GCD context.
        // Cap at 3 concurrent extractions, 10s timeout each.
        let semaphore = DispatchSemaphore(value: 0)
        var results: [(index: Int, html: String?)] = []
        let resultsLock = NSLock()

        Task {
            await withTaskGroup(of: (Int, String?).self) { group in
                var queued = 0
                for target in targets {
                    if queued >= 3 {
                        if let result = await group.next() {
                            resultsLock.lock()
                            results.append((index: result.0, html: result.1))
                            resultsLock.unlock()
                        }
                    }
                    let idx = target.index
                    let url = target.url
                    group.addTask {
                        let extracted = await withTaskGroup(of: String?.self) { inner -> String? in
                            inner.addTask {
                                return await ArticleExtractor.extract(from: url)
                            }
                            inner.addTask {
                                try? await Task.sleep(nanoseconds: 10_000_000_000)
                                return nil
                            }
                            for await result in inner {
                                if result != nil {
                                    inner.cancelAll()
                                    return result
                                }
                            }
                            return nil
                        }
                        return (idx, extracted)
                    }
                    queued += 1
                }
                for await result in group {
                    resultsLock.lock()
                    results.append((index: result.0, html: result.1))
                    resultsLock.unlock()
                }
            }
            semaphore.signal()
        }
        semaphore.wait()

        for result in results {
            if let html = result.html {
                let wordCount = html.strippingHTMLTags()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ").count
                if wordCount >= 200 {
                    items[result.index].contentHTML = html
                    NSLog("[EnrichVerge] %@ words: %d subscriber: false", items[result.index].url.absoluteString, wordCount)
                } else {
                    items[result.index].isSubscriberOnly = true
                    NSLog("[EnrichVerge] %@ words: %d subscriber: true (too short)", items[result.index].url.absoluteString, wordCount)
                }
            } else {
                items[result.index].isSubscriberOnly = true
                NSLog("[EnrichVerge] %@ words: 0 subscriber: true (extraction failed)", items[result.index].url.absoluteString)
            }
        }
    }

    // MARK: - Image Extraction Pipeline

    /// Step 1: og:image, twitter:image, og:image:url, og:image:secure_url
    private static let metaImagePatterns: [NSRegularExpression] = {
        let tags = [
            "og:image", "og:image:secure_url", "og:image:url",
            "twitter:image", "twitter:image:src",
        ]
        var patterns: [String] = []
        for tag in tags {
            let escaped = NSRegularExpression.escapedPattern(for: tag)
            // property="tag" ... content="url"
            patterns.append("(?:property|name)\\s*=\\s*[\"']\(escaped)[\"'][^>]*content\\s*=\\s*[\"']([^\"']+)[\"']")
            // content="url" ... property="tag"
            patterns.append("content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*(?:property|name)\\s*=\\s*[\"']\(escaped)[\"']")
        }
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static func extractMetaImage(from html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)
        for regex in metaImagePatterns {
            if let match = regex.firstMatch(in: html, range: range),
               let urlRange = Range(match.range(at: 1), in: html) {
                var url = String(html[urlRange])
                if url.hasPrefix("//") { url = "https:" + url }
                if url.hasPrefix("http") { return url }
            }
        }
        return nil
    }

    /// Step 2: <link rel="image_src">, <meta itemprop="image">, <meta name="thumbnail">
    private static let linkImagePatterns: [NSRegularExpression] = {
        let raw = [
            "<link[^>]+rel\\s*=\\s*[\"']image_src[\"'][^>]+href\\s*=\\s*[\"']([^\"']+)[\"']",
            "<meta[^>]+itemprop\\s*=\\s*[\"']image[\"'][^>]+content\\s*=\\s*[\"']([^\"']+)[\"']",
            "<meta[^>]+name\\s*=\\s*[\"']thumbnail[\"'][^>]+content\\s*=\\s*[\"']([^\"']+)[\"']",
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static func extractLinkImage(from html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)
        for regex in linkImagePatterns {
            if let match = regex.firstMatch(in: html, range: range),
               let urlRange = Range(match.range(at: 1), in: html) {
                var url = String(html[urlRange])
                if url.hasPrefix("//") { url = "https:" + url }
                if url.hasPrefix("http") { return url }
            }
        }
        return nil
    }

    /// Step 3: First real content image from page body.
    /// Filters out icons, logos, avatars, tracking pixels by checking
    /// URL patterns and explicit width/height attributes.
    private static let contentImgRegex: NSRegularExpression? =
        try? NSRegularExpression(
            pattern: "<img\\s[^>]*src\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
            options: .caseInsensitive
        )

    private static let skipImagePatterns: Set<String> = [
        "logo", "icon", "avatar", "badge", "emoji", "button", "spacer",
        "pixel", "tracking", "1x1", "blank", "spinner", "loading",
        "gravatar", "favicon", "sprite", "ads", "banner-ad",
        "data:", ".svg", ".gif", "placeholder", "lazy",
    ]

    private static func extractContentImage(from html: String, baseURL: URL) -> String? {
        guard let regex = contentImgRegex else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        for match in matches.prefix(20) {
            guard let srcRange = Range(match.range(at: 1), in: html) else { continue }
            let fullTag: String
            if let tagRange = Range(match.range(at: 0), in: html) {
                fullTag = String(html[tagRange]).lowercased()
            } else {
                fullTag = ""
            }
            var src = String(html[srcRange])
            let srcLower = src.lowercased()

            // Skip known junk patterns
            if skipImagePatterns.contains(where: { srcLower.contains($0) }) { continue }

            // Skip images with explicit tiny dimensions
            if let width = extractDimension("width", from: fullTag), width < 100 { continue }
            if let height = extractDimension("height", from: fullTag), height < 80 { continue }

            // Resolve relative URLs
            if src.hasPrefix("//") {
                src = "https:" + src
            } else if src.hasPrefix("/") {
                if let scheme = baseURL.scheme, let host = baseURL.host {
                    src = "\(scheme)://\(host)\(src)"
                }
            }

            if src.hasPrefix("http") { return src }
        }
        return nil
    }

    // Pre-compiled dimension regexes — avoids recompilation per image tag
    private static let widthRegex = try? NSRegularExpression(pattern: "width\\s*=\\s*[\"']?(\\d+)", options: .caseInsensitive)
    private static let heightRegex = try? NSRegularExpression(pattern: "height\\s*=\\s*[\"']?(\\d+)", options: .caseInsensitive)

    /// Extracts a numeric dimension from an img tag attribute (e.g., width="120" or width: 120px)
    private static func extractDimension(_ attr: String, from tag: String) -> Int? {
        let regex = attr == "width" ? widthRegex : heightRegex
        guard let regex = regex else { return nil }
        let range = NSRange(tag.startIndex..., in: tag)
        if let match = regex.firstMatch(in: tag, range: range),
           let numRange = Range(match.range(at: 1), in: tag),
           let num = Int(tag[numRange]) {
            return num
        }
        return nil
    }
}

// MARK: - XML Parser Delegate

private enum FeedFormat {
    case rss, atom, unknown
}

private class FeedXMLParserDelegate: NSObject, XMLParserDelegate {
    let sourceName: String
    let category: String
    let isVideo: Bool
    let isShort: Bool
    var items: [FeedItem] = []

    private var feedFormat: FeedFormat = .unknown
    private var isInsideItem = false
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentLink = ""
    private var currentPubDate = ""
    private var currentImageURL = ""
    private var currentContentEncoded = ""
    private var currentVideoId = ""

    init(sourceName: String, category: String, isVideo: Bool = false, isShort: Bool = false) {
        self.sourceName = sourceName
        self.category = category
        self.isVideo = isVideo
        self.isShort = isShort
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {

        let qualified = qName ?? elementName

        if elementName == "rss" { feedFormat = .rss }
        if elementName == "feed" { feedFormat = .atom }

        if elementName == "item" || elementName == "entry" {
            isInsideItem = true
            currentTitle = ""
            currentDescription = ""
            currentLink = ""
            currentPubDate = ""
            currentImageURL = ""
            currentContentEncoded = ""
            currentVideoId = ""
        }

        if isInsideItem {
            // Only update currentElement for tags we actually collect text from.
            // This prevents nested child elements (e.g., <div> inside <summary>)
            // from overwriting currentElement, which would cause text after
            // the child's close tag to be dropped.
            let trackedElements: Set<String> = [
                "title", "description", "summary", "content", "encoded",
                "link", "pubDate", "published", "updated", "videoId",
            ]
            if trackedElements.contains(elementName) {
                currentElement = elementName
            }

            // Reset date when a date element starts.
            // pubDate/published always reset; updated only resets if no date yet.
            if elementName == "pubDate" || elementName == "published" {
                currentPubDate = ""
            } else if elementName == "updated" && currentPubDate.isEmpty {
                currentPubDate = ""
            }

            if feedFormat == .atom && elementName == "link" {
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" || currentLink.isEmpty {
                        currentLink = href
                    }
                }
            }

            if qualified == "media:thumbnail" {
                // Prefer media:thumbnail — it's always an image
                if let url = attributeDict["url"] {
                    currentImageURL = url
                }
            } else if qualified == "media:content" {
                // Only use media:content if its type is an image (YouTube's is application/x-shockwave-flash)
                if let type = attributeDict["type"], type.hasPrefix("image"),
                   let url = attributeDict["url"], currentImageURL.isEmpty {
                    currentImageURL = url
                }
            }

            if elementName == "enclosure" {
                if let type = attributeDict["type"], type.hasPrefix("image"),
                   let url = attributeDict["url"], currentImageURL.isEmpty {
                    currentImageURL = url
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "description", "summary", "content": currentDescription += string
        case "encoded", "content:encoded": currentContentEncoded += string
        case "link": currentLink += string
        case "pubDate", "published":
            currentPubDate += string
        case "updated":
            // Only use updated if no pubDate/published was found
            if currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                currentPubDate += string
            }
        case "yt:videoId", "videoId":
            currentVideoId += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {

        if elementName == "item" || elementName == "entry" {
            isInsideItem = false

            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).strippingHTMLTags()
            let rawDescription = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = rawDescription.strippingHTMLTags()
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            var imageURLString = currentImageURL.trimmingCharacters(in: .whitespacesAndNewlines)

            if imageURLString.isEmpty {
                let htmlSources = [currentContentEncoded, rawDescription]
                for html in htmlSources {
                    if let extracted = Self.extractFirstImageURL(from: html) {
                        imageURLString = extracted
                        break
                    }
                }
            }

            guard !title.isEmpty, let url = URL(string: link) else { return }

            let pubDate = DateParsing.parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            var imageURL = imageURLString.isEmpty ? nil : URL(string: imageURLString)

            // Auto-extract YouTube thumbnails for video feeds
            if isVideo, imageURL == nil {
                let videoID = currentVideoId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !videoID.isEmpty {
                    imageURL = URL(string: "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg")
                } else if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let vid = components.queryItems?.first(where: { $0.name == "v" })?.value {
                    imageURL = URL(string: "https://img.youtube.com/vi/\(vid)/maxresdefault.jpg")
                }
            }

            // Techmeme is a link aggregator — its <link> points to Techmeme's own page,
            // but the actual source article URL is in the first <a href> of the description.
            var articleURL = url
            if sourceName == "Techmeme" {
                if let sourceURL = Self.extractTechmemeSourceURL(from: rawDescription) {
                    articleURL = sourceURL
                }
            }

            var item = FeedItem(
                title: title,
                itemDescription: desc,
                url: articleURL,
                imageURL: imageURL,
                source: sourceName,
                category: category,
                pubDate: pubDate
            )
            item.isVideo = isVideo
            item.isShort = isShort
            // Store full HTML for native reader — prefer content:encoded, fall back to raw description
            let contentEncoded = currentContentEncoded.trimmingCharacters(in: .whitespacesAndNewlines)
            item.contentHTML = contentEncoded.isEmpty ? rawDescription : contentEncoded
            items.append(item)
        }

        if isInsideItem && elementName == currentElement {
            currentElement = ""
        }
    }

    /// Extract the actual source article URL from Techmeme's description HTML.
    /// Techmeme embeds the source URL as the first <a href="..."> pointing to an external site.
    private static func extractTechmemeSourceURL(from html: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: "<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"']",
            options: .caseInsensitive
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)
        for match in matches.prefix(5) {
            guard let urlRange = Range(match.range(at: 1), in: html) else { continue }
            let urlStr = String(html[urlRange])
            // Skip links back to Techmeme itself
            if urlStr.contains("techmeme.com") { continue }
            if let url = URL(string: urlStr), urlStr.hasPrefix("http") {
                return url
            }
        }
        return nil
    }

    private static let imgSrcRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']", options: .caseInsensitive)

    private static func extractFirstImageURL(from html: String) -> String? {
        guard !html.isEmpty, let regex = imgSrcRegex else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let urlRange = Range(match.range(at: 1), in: html) else { return nil }
        let url = String(html[urlRange])
        return url.isEmpty ? nil : url
    }
}

// MARK: - Date Parsing

enum DateParsing {
    static let formatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.dateFormat = format
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }
    }()

    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date {
        for formatter in formatters {
            if let date = formatter.date(from: string) { return date }
        }
        if let date = isoFractional.date(from: string) { return date }
        if let date = isoStandard.date(from: string) { return date }
        // Return distant past so unparseable dates sort to the bottom, not the top
        return Date.distantPast
    }
}

// MARK: - HTML Stripping

extension String {
    // Pre-compiled regexes — avoids recompilation on every feed item
    private static let htmlTagRegex = try? NSRegularExpression(pattern: "<[^>]+>")
    private static let decimalEntityRegex = try? NSRegularExpression(pattern: "&#(\\d+);")
    private static let hexEntityRegex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);")

    private static let namedEntities: [(String, String)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
        ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
        ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
        ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ("&hellip;", "\u{2026}"), ("&trade;", "\u{2122}"),
        ("&copy;", "\u{00A9}"), ("&reg;", "\u{00AE}"),
    ]

    func strippingHTMLTags() -> String {
        var result: String
        if let regex = Self.htmlTagRegex {
            let range = NSRange(self.startIndex..., in: self)
            result = regex.stringByReplacingMatches(in: self, range: range, withTemplate: "")
        } else {
            result = self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }

        for (entity, replacement) in Self.namedEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Decode numeric decimal entities: &#8217; &#160; etc.
        if let decRegex = Self.decimalEntityRegex {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = decRegex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[codeRange]),
                      let scalar = Unicode.Scalar(code),
                      let fullRange = Range(match.range(at: 0), in: result) else { continue }
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }

        // Decode numeric hex entities: &#x27; &#x2F; etc.
        if let hexRegex = Self.hexEntityRegex {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = hexRegex.matches(in: result, range: nsRange).reversed()
            for match in matches {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[codeRange], radix: 16),
                      let scalar = Unicode.Scalar(code),
                      let fullRange = Range(match.range(at: 0), in: result) else { continue }
                result.replaceSubrange(fullRange, with: String(scalar))
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
