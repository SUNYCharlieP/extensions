import Foundation
import Combine

class PodcastParser: ObservableObject {
    @Published var episodes: [PodcastEpisode] = []
    @Published var isLoading = false

    private let lock = NSLock()

    func fetchAllPodcasts() {
        guard !isLoading else { return }
        isLoading = true
        var collected: [PodcastEpisode] = []
        let group = DispatchGroup()

        for feed in PodcastFeed.allFeeds {
            guard let url = URL(string: feed.url) else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
                defer { group.leave() }
                guard let self = self, let data = data, error == nil else { return }

                let delegate = PodcastXMLParserDelegate(
                    sourceName: feed.name,
                    fallbackArtwork: feed.artworkURL,
                    episodeType: feed.episodeType
                )
                let parser = XMLParser(data: data)
                parser.delegate = delegate
                parser.parse()

                self.lock.lock()
                collected.append(contentsOf: delegate.episodes)
                self.lock.unlock()
            }.resume()
        }

        group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            // Sort by date, newest first. Limit to recent episodes.
            let sorted = collected
                .sorted { $0.pubDate > $1.pubDate }
                .prefix(100)
            self.lock.unlock()

            DispatchQueue.main.async {
                self.episodes = Array(sorted)
                self.isLoading = false
                let continuations = self.pendingContinuations
                self.pendingContinuations.removeAll()
                for c in continuations { c.resume() }
            }
        }
    }

    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []

    func fetchAllPodcastsAsync() async {
        await withCheckedContinuation { continuation in
            let work = {
                if self.isLoading {
                    self.pendingContinuations.append(continuation)
                    return
                }
                self.pendingContinuations.append(continuation)
                self.fetchAllPodcasts()
            }
            if Thread.isMainThread {
                work()
            } else {
                DispatchQueue.main.async { work() }
            }
        }
    }

    var snippets: [PodcastEpisode] {
        episodes.filter { $0.episodeType == .snippet }
    }

    var briefings: [PodcastEpisode] {
        episodes.filter { $0.episodeType == .briefing }
    }

    var fullEpisodes: [PodcastEpisode] {
        episodes.filter { $0.episodeType == .fullEpisode }
    }
}

// MARK: - Podcast XML Parser

private class PodcastXMLParserDelegate: NSObject, XMLParserDelegate {
    var episodes: [PodcastEpisode] = []

    private let sourceName: String
    private let fallbackArtwork: String
    private let episodeType: PodcastEpisode.EpisodeType

    private var isInsideItem = false
    private var isInsideChannel = true
    private var currentElement = ""

    // Channel-level data
    private var channelArtworkURL = ""

    // Item-level data
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentAudioURL = ""
    private var currentAudioType = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentImageURL = ""

    init(sourceName: String, fallbackArtwork: String, episodeType: PodcastEpisode.EpisodeType) {
        self.sourceName = sourceName
        self.fallbackArtwork = fallbackArtwork
        self.episodeType = episodeType
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {

        let qualified = qName ?? elementName

        if elementName == "item" {
            isInsideItem = true
            isInsideChannel = false
            currentElement = ""
            currentTitle = ""
            currentDescription = ""
            currentAudioURL = ""
            currentAudioType = ""
            currentPubDate = ""
            currentDuration = ""
            currentImageURL = ""
        }

        if isInsideItem {
            let tracked: Set<String> = ["title", "description", "summary", "pubDate", "published", "duration"]
            if tracked.contains(elementName) {
                currentElement = elementName
            }

            if elementName == "pubDate" || elementName == "published" {
                currentPubDate = ""
            }

            // Audio enclosure — the key tag for podcast episodes
            if elementName == "enclosure" {
                if let type = attributeDict["type"], type.hasPrefix("audio"),
                   let url = attributeDict["url"] {
                    currentAudioURL = url
                    currentAudioType = type
                }
            }

            // Episode-level artwork
            if qualified == "itunes:image" || qualified == "image" {
                if let href = attributeDict["href"], !href.isEmpty {
                    currentImageURL = href
                }
            }

            // itunes:duration — text content or rarely an attribute
            if elementName == "duration" || qualified == "itunes:duration" {
                currentElement = "duration"
                currentDuration = ""
            }
        } else if isInsideChannel {
            // Channel-level artwork
            if qualified == "itunes:image" {
                if let href = attributeDict["href"], !href.isEmpty {
                    channelArtworkURL = href
                }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title": currentTitle += string
        case "description", "summary": currentDescription += string
        case "pubDate", "published": currentPubDate += string
        case "duration": currentDuration += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {

        if elementName == "item" {
            isInsideItem = false

            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines).strippingHTMLTags()
            let audioURLString = currentAudioURL.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, !audioURLString.isEmpty,
                  let audioURL = URL(string: audioURLString) else { return }

            let pubDate = DateParsing.parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            let duration = parseDuration(currentDuration.trimmingCharacters(in: .whitespacesAndNewlines))

            // Artwork: episode-level > channel-level > fallback
            let artworkString = !currentImageURL.isEmpty ? currentImageURL :
                                !channelArtworkURL.isEmpty ? channelArtworkURL :
                                fallbackArtwork
            let artworkURL = artworkString.isEmpty ? nil : URL(string: artworkString)

            let episode = PodcastEpisode(
                title: title,
                episodeDescription: desc,
                audioURL: audioURL,
                duration: duration,
                pubDate: pubDate,
                source: sourceName,
                artworkURL: artworkURL,
                episodeType: episodeType
            )
            episodes.append(episode)
        }

        if isInsideItem && !currentElement.isEmpty &&
            (elementName == currentElement || elementName.hasSuffix(":" + currentElement)) {
            currentElement = ""
        }
    }

    /// Parse iTunes duration — can be "HH:MM:SS", "MM:SS", or just seconds (possibly decimal)
    private func parseDuration(_ str: String) -> TimeInterval {
        if str.isEmpty { return 0 }

        // If no colons, treat as raw seconds (may be decimal like "3723.5")
        if !str.contains(":") {
            return Double(str) ?? 0
        }

        let parts = str.split(separator: ":").compactMap { Int(Double($0) ?? 0) }
        switch parts.count {
        case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        case 2: return TimeInterval(parts[0] * 60 + parts[1])
        case 1: return TimeInterval(parts[0])
        default: return 0
        }
    }
}

// MARK: - Reuse DateParsing from FeedParser

// DateParsing is defined in FeedParser.swift and is file-private.
// We need it accessible here too, so we use a small extension.
// The strippingHTMLTags() extension is also in FeedParser.swift.
