import Foundation

struct PodcastEpisode: Identifiable, Equatable {
    var id: String { audioURL.absoluteString }

    static func == (lhs: PodcastEpisode, rhs: PodcastEpisode) -> Bool {
        lhs.audioURL == rhs.audioURL
    }

    let title: String
    let episodeDescription: String
    let audioURL: URL
    let duration: TimeInterval // seconds, 0 if unknown
    let pubDate: Date
    let source: String
    var artworkURL: URL?
    var episodeType: EpisodeType = .fullEpisode

    enum EpisodeType: String {
        case snippet    // 1-5 min news bulletins
        case briefing   // 10-15 min daily recaps
        case fullEpisode // 30-60 min full shows
    }

    var durationString: String {
        if duration < 1 { return "" } // unknown duration
        let mins = Int(duration) / 60
        if mins < 1 { return "< 1 min" }
        if mins < 60 { return "\(mins) min" }
        let hrs = mins / 60
        let rem = mins % 60
        return rem > 0 ? "\(hrs)h \(rem)m" : "\(hrs)h"
    }
}

struct PodcastFeed {
    let name: String
    let url: String
    let artworkURL: String
    let episodeType: PodcastEpisode.EpisodeType

    static let allFeeds: [PodcastFeed] = [
        // Snippets (1-5 min)
        PodcastFeed(
            name: "NPR News Now",
            url: "https://feeds.npr.org/500005/podcast.xml",
            artworkURL: "",
            episodeType: .snippet
        ),
        // Briefings (10-15 min)
        PodcastFeed(
            name: "Techmeme Ride Home",
            url: "https://feeds.megaphone.fm/techmeme-ridehome",
            artworkURL: "",
            episodeType: .briefing
        ),
        PodcastFeed(
            name: "WSJ Tech News Briefing",
            url: "https://feeds.megaphone.fm/WSJ8022486498",
            artworkURL: "",
            episodeType: .briefing
        ),
        // Full Episodes (30-60 min)
        PodcastFeed(
            name: "The Vergecast",
            url: "https://feeds.megaphone.fm/vergecast",
            artworkURL: "",
            episodeType: .fullEpisode
        ),
        PodcastFeed(
            name: "Waveform: The MKBHD Podcast",
            url: "https://feeds.megaphone.fm/waveform",
            artworkURL: "",
            episodeType: .fullEpisode
        ),
        PodcastFeed(
            name: "Hard Fork",
            url: "https://feeds.simplecast.com/l2i9YnTd",
            artworkURL: "",
            episodeType: .fullEpisode
        ),
        PodcastFeed(
            name: "Decoder with Nilay Patel",
            url: "https://feeds.megaphone.fm/decoder",
            artworkURL: "",
            episodeType: .fullEpisode
        ),
        PodcastFeed(
            name: "Accidental Tech Podcast",
            url: "https://atp.fm/episodes?format=rss",
            artworkURL: "",
            episodeType: .fullEpisode
        ),
    ]
}
