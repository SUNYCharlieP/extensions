import AVFoundation
import MediaPlayer
import Combine

class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    @Published var currentEpisode: PodcastEpisode?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var isBuffering = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var artworkTask: URLSessionDataTask?

    private init() {
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - Playback Controls

    func play(_ episode: PodcastEpisode) {
        // If same episode, just resume
        if let current = currentEpisode, current.audioURL == episode.audioURL {
            resume()
            return
        }

        // Clean up previous player completely
        stop()

        currentEpisode = episode
        isBuffering = true

        let playerItem = AVPlayerItem(url: episode.audioURL)
        player = AVPlayer(playerItem: playerItem)
        // Don't set rate here — wait for readyToPlay status observer

        // Observe when item is ready
        let episodeID = episode.audioURL
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self,
                      self.currentEpisode?.audioURL == episodeID else { return }
                if status == .readyToPlay {
                    self.isBuffering = false
                    self.duration = playerItem.duration.seconds.isFinite
                        ? playerItem.duration.seconds
                        : episode.duration
                    // Setting rate to non-zero starts playback — no need for play() first
                    self.player?.rate = self.playbackRate
                    self.isPlaying = true
                    self.updateNowPlaying()
                } else if status == .failed {
                    self.isBuffering = false
                    self.isPlaying = false
                    self.currentEpisode = nil
                }
            }
            .store(in: &cancellables)

        // Observe buffering state — only when actively playing
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                guard let self = self, self.isPlaying else { return }
                self.isBuffering = empty
            }
            .store(in: &cancellables)

        // Time observer — update every 0.5 seconds
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = time.seconds
            if seconds.isFinite {
                self.currentTime = seconds
            }
        }

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.isBuffering = false
                self?.currentTime = 0
                self?.updateNowPlaying()
            }
            .store(in: &cancellables)
    }

    func resume() {
        player?.rate = playbackRate // non-zero rate starts playback without 1x glitch
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func stop() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        artworkTask?.cancel()
        artworkTask = nil
        player?.pause()
        player = nil
        cancellables.removeAll()
        isPlaying = false
        currentTime = 0
        duration = 0
        isBuffering = false
        currentEpisode = nil
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlaying()
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        let target = min(currentTime + seconds, duration)
        seek(to: target)
    }

    func skipBackward(_ seconds: TimeInterval = 15) {
        let target = max(currentTime - seconds, 0)
        seek(to: target)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlaying()
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Now Playing Info (Lock Screen)

    private func updateNowPlaying() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.source,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0,
        ]

        // Load artwork asynchronously — cancel previous request
        artworkTask?.cancel()
        if let artworkURL = episode.artworkURL {
            let episodeID = episode.audioURL
            artworkTask = URLSession.shared.dataTask(with: artworkURL) { [weak self] data, _, error in
                guard error == nil, let data = data, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    // Only update if still playing the same episode
                    guard self?.currentEpisode?.audioURL == episodeID else { return }
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    current[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                }
            }
            artworkTask?.resume()
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Remote Commands (Lock Screen / AirPods)

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: event.positionTime)
            return .success
        }
    }
}
