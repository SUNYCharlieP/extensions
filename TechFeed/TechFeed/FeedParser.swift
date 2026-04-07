import Foundation

class FeedParser: ObservableObject {
    @Published var items: [FeedItem] = []
    @Published var isLoading: Bool = false

    private let lock = NSLock()
    private var collectedItems: [FeedItem] = []

    func fetchAllFeeds() {
        DispatchQueue.main.async {
            self.isLoading = true
        }

        lock.lock()
        collectedItems = []
        lock.unlock()

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
                self.collectedItems.append(contentsOf: delegate.items)
                self.lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.items = self.collectedItems.sorted { $0.pubDate > $1.pubDate }
            self.collectedItems = []
            self.isLoading = false
        }
    }

    func fetchAllFeedsAsync() async {
        fetchAllFeeds()
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
        }

        if isInsideItem {
            currentElement = elementName

            // Atom link
            if feedFormat == .atom && elementName == "link" {
                if let href = attributeDict["href"] {
                    let rel = attributeDict["rel"] ?? "alternate"
                    if rel == "alternate" || currentLink.isEmpty {
                        currentLink = href
                    }
                }
            }

            // Media namespace images
            if qualified == "media:content" || qualified == "media:thumbnail" {
                if let url = attributeDict["url"], currentImageURL.isEmpty {
                    currentImageURL = url
                }
            }

            // Enclosure images
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
            let desc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines).strippingHTMLTags()
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURLString = currentImageURL.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, let url = URL(string: link) else { return }

            let pubDate = parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
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
}

// MARK: - Date Parsing

private func parseDate(_ string: String) -> Date {
    let formatters: [DateFormatter] = {
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

    for formatter in formatters {
        if let date = formatter.date(from: string) {
            return date
        }
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: string) { return date }

    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: string) { return date }

    return Date()
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
