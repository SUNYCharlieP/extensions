import SwiftUI

struct ListenTab: View {
    @StateObject private var podcastParser = PodcastParser()
    @ObservedObject private var player = AudioPlayerManager.shared
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header matching home feed style
                listenHeader

                if podcastParser.isLoading && podcastParser.episodes.isEmpty {
                    loadingState
                } else if podcastParser.episodes.isEmpty {
                    emptyState
                } else {
                    // Quick Listen — snippets
                    if !podcastParser.snippets.isEmpty {
                        quickListenSection
                            .padding(.top, 16)
                    }

                    // Briefings
                    if !podcastParser.briefings.isEmpty {
                        episodeSection(
                            title: "Daily Briefings",
                            subtitle: "10-15 min tech recaps",
                            icon: "clock.badge.checkmark",
                            episodes: podcastParser.briefings
                        )
                        .padding(.top, 20)
                    }

                    // Full Episodes
                    if !podcastParser.fullEpisodes.isEmpty {
                        episodeSection(
                            title: "Full Episodes",
                            subtitle: "Deep dives & discussions",
                            icon: "headphones",
                            episodes: podcastParser.fullEpisodes
                        )
                        .padding(.top, 20)
                    }
                }
            }
            .padding(.bottom, player.currentEpisode != nil ? 80 : 20)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await podcastParser.fetchAllPodcastsAsync()
        }
        .onAppear {
            if podcastParser.episodes.isEmpty {
                podcastParser.fetchAllPodcasts()
            }
        }
    }

    private var listenHeader: some View {
        ZStack {
            LinearGradient(
                colors: [.arcaOrange, Color(red: 1.0, green: 0.33, blue: 0.27), .arcaRed],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)

            HStack {
                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: "headphones")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                    Text("Listen")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(height: 56)
    }

    // MARK: - Quick Listen (Horizontal Scroll)

    private var quickListenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.arcaOrange)
                Text("Quick Listen")
                    .font(.title3.weight(.bold))
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(podcastParser.snippets.prefix(10)) { episode in
                        SnippetCard(episode: episode) {
                            player.play(episode)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Episode Section (Vertical List)

    private func episodeSection(title: String, subtitle: String, icon: String, episodes: [PodcastEpisode]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.arcaOrange)
                    Text(title)
                        .font(.title3.weight(.bold))
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            ForEach(episodes.prefix(15)) { episode in
                EpisodeRow(episode: episode) {
                    player.play(episode)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ArcaLoadingView()
                .scaleEffect(0.7)
            Text("Loading podcasts...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "headphones")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No podcasts available")
                .font(.headline)
                .foregroundColor(.gray)
            Button("Try Again") {
                podcastParser.fetchAllPodcasts()
            }
            .foregroundColor(.arcaOrange)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Snippet Card (Horizontal)

private struct SnippetCard: View {
    let episode: PodcastEpisode
    let onPlay: () -> Void
    @ObservedObject private var player = AudioPlayerManager.shared

    private var isCurrentlyPlaying: Bool {
        player.currentEpisode?.audioURL == episode.audioURL && player.isPlaying
    }

    var body: some View {
        Button(action: {
            if isCurrentlyPlaying {
                player.pause()
            } else {
                onPlay()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Artwork
                ZStack {
                    if let artworkURL = episode.artworkURL {
                        CachedAsyncImage(url: artworkURL)
                            .scaledToFill()
                            .frame(width: 140, height: 140)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.arcaOrange.opacity(0.15))
                            .frame(width: 140, height: 140)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.title)
                                    .foregroundColor(.arcaOrange)
                            )
                    }

                    // Play indicator
                    if isCurrentlyPlaying {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "pause.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.source)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.arcaOrange)
                    Text(episode.title)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(episode.durationString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Episode Row (Vertical)

private struct EpisodeRow: View {
    let episode: PodcastEpisode
    let onPlay: () -> Void
    @ObservedObject private var player = AudioPlayerManager.shared

    private var isCurrentlyPlaying: Bool {
        player.currentEpisode?.audioURL == episode.audioURL && player.isPlaying
    }

    var body: some View {
        Button(action: {
            if isCurrentlyPlaying {
                player.pause()
            } else {
                onPlay()
            }
        }) {
            HStack(spacing: 12) {
                // Artwork
                ZStack {
                    if let artworkURL = episode.artworkURL {
                        CachedAsyncImage(url: artworkURL)
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.arcaOrange.opacity(0.15))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "waveform")
                                    .foregroundColor(.arcaOrange)
                            )
                    }

                    if isCurrentlyPlaying {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "pause.fill")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.source)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.arcaOrange)
                    Text(episode.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(episode.durationString)
                        Text("·")
                        Text(episode.pubDate.relativeString)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.arcaOrange)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full Player View (Sheet)

struct FullPlayerView: View {
    let episode: PodcastEpisode
    @ObservedObject private var player = AudioPlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 24) {
            // Drag handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            Spacer()

            // Artwork
            if let artworkURL = episode.artworkURL {
                CachedAsyncImage(url: artworkURL)
                    .scaledToFill()
                    .frame(width: 280, height: 280)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .id(episode.id)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.arcaOrange.opacity(0.15))
                    .frame(width: 280, height: 280)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 60))
                            .foregroundColor(.arcaOrange)
                    )
            }

            // Title & source
            VStack(spacing: 6) {
                Text(episode.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text(episode.source)
                    .font(.subheadline)
                    .foregroundColor(.arcaOrange)
            }
            .padding(.horizontal)

            // Progress bar
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .tint(.arcaOrange)

                HStack {
                    Text(formatTime(player.currentTime))
                    Spacer()
                    Text("-" + formatTime(max(0, player.duration - player.currentTime)))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)

            // Playback controls
            HStack(spacing: 40) {
                Button { player.skipBackward() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(.primary)
                }

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.arcaOrange)
                }

                Button { player.skipForward() } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }

            // Speed control
            HStack(spacing: 12) {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        player.setRate(rate)
                    } label: {
                        Text(rate == 1.0 ? "1x" : String(format: "%.2g", rate) + "x")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                player.playbackRate == rate
                                    ? Color.arcaOrange
                                    : Color(.tertiarySystemGroupedBackground)
                            )
                            .foregroundColor(
                                player.playbackRate == rate ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Mini Player Bar

struct MiniPlayerBar: View {
    @ObservedObject private var player = AudioPlayerManager.shared
    let onTap: () -> Void

    var body: some View {
        if let episode = player.currentEpisode {
            HStack(spacing: 12) {
                // Artwork + title area — tappable to open full player
                HStack(spacing: 12) {
                    if let artworkURL = episode.artworkURL {
                        CachedAsyncImage(url: artworkURL)
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .id(episode.id)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.arcaOrange.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundColor(.arcaOrange)
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(episode.source)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .onTapGesture { onTap() }

                Spacer()

                if player.isBuffering {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundColor(.arcaOrange)
                    }

                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.arcaOrange)
                        .frame(width: geo.size.width * player.progress, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
