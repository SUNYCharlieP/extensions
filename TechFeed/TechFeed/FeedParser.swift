import Foundation

class FeedParser: ObservableObject {
    @Published var items: [FeedItem] = []
    @Published var isLoading: Bool = false

    private let lock = NSLock()
    private let preferences = PreferenceEngine.shared
    private let ogImageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    func fetchAllFeeds() {
        guard !isLoading else { return }
        isLoading = true
        var collectedItems: [FeedItem] = []
        let group = DispatchGroup()

        for feed in RSSFeed.allFeeds {
            guard let url = URL(string: feed.url) else { continue }
            group.enter()
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                defer { group.leave() }
                guard let self = self, let data = data, error == nil else { return }

                let delegate = FeedXMLParserDelegate(sourceName: feed.name)
                let parser = XMLParser(data: data)
                parser.delegate = delegate
                parser.parse()

                self.lock.lock()
                collectedItems.append(contentsOf: delegate.items)
                self.lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            let sorted = self.preferences.scoreItems(collectedItems)
            self.items = sorted
            self.isLoading = false
            self.fetchMissingImages()
        }
    }

    func fetchAllFeedsAsync() async {
        fetchAllFeeds()
    }

    private func fetchMissingImages() {
        let missing = items.filter { $0.imageURL == nil }
        guard !missing.isEmpty else { return }

        for item in missing {
            let itemID = item.id
            let articleURL = item.url
            var request = URLRequest(url: articleURL)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

            ogImageSession.dataTask(with: request) { [weak self] data, _, _ in
                guard let data = data,
                      let html = String(data: data.prefix(50_000), encoding: .utf8),
                      let ogImage = Self.extractOGImage(from: html),
                      let imageURL = URL(string: ogImage) else { return }

                DispatchQueue.main.async {
                    guard let self = self,
                          let idx = self.items.firstIndex(where: { $0.id == itemID }) else { return }
                    self.items[idx].imageURL = imageURL
                }
            }.resume()
        }
    }

    private static let ogImagePatterns: [NSRegularExpression] = {
        let raw = [
            "property\\s*=\\s*[\"']og:image[\"'][^>]*content\\s*=\\s*[\"']([^\"']+)[\"']",
            "content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*property\\s*=\\s*[\"']og:image[\"']",
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private static func extractOGImage(from html: String) -> String? {
        let range = NSRange(html.startIndex..., in: html)
        for regex in ogImagePatterns {
            if let match = regex.firstMatch(in: html, range: range),
               let urlRange = Range(match.range(at: 1), in: html) {
                let url = String(html[urlRange])
                if url.hasPrefix("http") { return url }
            }
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

    init(sourceName: String) {
        self.sourceName = sourceName
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
        }

        if isInsideItem {
            currentElement = elementName

            if feedFormat == .atom && elementName == "link" {
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" || currentLink.isEmpty {
                        currentLink = href
                    }
                }
            }

            if qualified == "media:content" || qualified == "media:thumbnail" {
                if let url = attributeDict["url"], currentImageURL.isEmpty {
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
        case "encoded": currentContentEncoded += string
        case "link": currentLink += string
        case "pubDate", "published", "updated":
            if currentPubDate.isEmpty || currentElement == "published" || currentElement == "pubDate" {
                currentPubDate += string
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {

        if elementName == "item" || elementName == "entry" {
            isInsideItem = false

            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let imageURL = imageURLString.isEmpty ? nil : URL(string: imageURLString)

            let item = FeedItem(
                title: title,
                itemDescription: desc,
                url: url,
                imageURL: imageURL,
                source: sourceName,
                pubDate: pubDate
            )
            items.append(item)
        }

        if isInsideItem {
            currentElement = ""
        }
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

private enum DateParsing {
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
        return Date()
    }
}

// MARK: - HTML Stripping

extension String {
    func strippingHTMLTags() -> String {
        let stripped = self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "\u{201C}")
            .replacingOccurrences(of: "&#8221;", with: "\u{201D}")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
