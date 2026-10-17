@preconcurrency import AVFoundation
import Combine
import SwiftUI

@MainActor
@Observable
class PlaybackState {
    // MARK: - Published Properties

    var isPlaying = false
    var currentTime: CMTime = .zero
    var duration: CMTime = .zero
    var player: AVPlayer?
    var isPreparingComposition = false

    // MARK: - In/Out Points (for selection range)

    var inPoint: CMTime?

    var outPoint: CMTime?

    func clearInOutPoints() {
        inPoint = nil
        outPoint = nil
    }

    /// Returns the selected range if both in and out points are set
    var selectedRange: CMTimeRange? {
        guard let inPoint = inPoint, let outPoint = outPoint else { return nil }
        let start = min(inPoint, outPoint)
        let end = max(inPoint, outPoint)
        return CMTimeRange(start: start, end: end)
    }

    // MARK: - Internal Properties

    private var timeObserver: Any?
    private var playbackEndedObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    // Releases player resources and security scope. A plain class, not MainActor, because its deinit must be nonisolated.
    private class TokenHolder {
        weak var player: AVPlayer?
        var observer: Any?

        // Without held security-scoped access, files from Downloads or external drives may fail to play.
        private var accessedURL: URL?

        func startAccessing(_ url: URL) {
            stopAccessing()

            if url.startAccessingSecurityScopedResource() {
                accessedURL = url
            }
        }

        func stopAccessing() {
            if let url = accessedURL {
                url.stopAccessingSecurityScopedResource()
                accessedURL = nil
            }
        }

        deinit {
            // stopAccessingSecurityScopedResource is thread-safe, so release inline to avoid actor isolation issues.
            if let url = accessedURL {
                url.stopAccessingSecurityScopedResource()
            }
            if let observer, let player {
                player.removeTimeObserver(observer)
            }
        }
    }

    private var tokenHolder = TokenHolder()

    // Task.cancel() is thread-safe, so we can call it from any thread in deinit
    // TokenHolder handles observer cleanup via its own deinit
    deinit {
        loadingTask?.cancel()
    }

    private func setupAudioSession() {
        // macOS needs no audio session setup.
    }

    // MARK: - Player Management

    func loadClip(_ clip: VideoClip) {
        // Also releases the previous security scope.
        unload()

        // TokenHolder releases it on unload or the next load.
        tokenHolder.startAccessing(clip.url)

        let playerItem = AVPlayerItem(url: clip.url)
        setupPlayer(with: playerItem, duration: clip.duration)

        AppLogger.playback.info("Loaded clip \(clip.url.lastPathComponent)")
    }

    // Debounce properties to avoid double-loading
    // Track clip IDs, not just count, to detect when clips change
    private var lastLoadedProjectID: UUID?
    private var lastLoadedClipsHash: Int = 0

    // Track loading task for cancellation on rapid reload
    // nonisolated(unsafe) required for deinit access from any thread
    @ObservationIgnored nonisolated(unsafe) private var loadingTask: Task<Void, Never>?

    // Deferred loading - store pending project for lazy composition
    private var pendingProject: VideoProject?
    private var isCompositionReady: Bool = false

    private let projectSwitchDebounceDelay: UInt64 = 300_000_000 // 300ms
    private let editDebounceDelay: UInt64 = 120_000_000 // 120ms (keeps timeline edits feeling responsive)

    /// Reset playback state - call when switching projects
    func reset() {
        loadingTask?.cancel()
        loadingTask = nil
        pendingProject = nil
        isCompositionReady = false
        isPreparingComposition = false
        unload()
        lastLoadedProjectID = nil
        lastLoadedClipsHash = 0
        AppLogger.playback.debug("PlaybackState reset")
    }

    func loadProject(_ project: VideoProject, forceReload: Bool = false) {
        // Composing an empty timeline freezes, so skip it.
        let hasClips = project.timeline.tracks.contains { !$0.clips.isEmpty }
        guard hasClips else {
            AppLogger.playback.debug("loadProject called with empty timeline - skipping composition")
            unload()
            pendingProject = nil
            isCompositionReady = false
            isPreparingComposition = false
            return
        }

        var hasher = Hasher()
        hasher.combine(project.captionOffset.width)
        hasher.combine(project.captionOffset.height)
        hasher.combine(project.captionStyleName)
        hasher.combine(project.captionFontName)

        for track in project.timeline.tracks {
            for clip in track.clips {
                hasher.combine(clip)
            }
        }
        let currentClipsHash = hasher.finalize()

        if !forceReload, lastLoadedProjectID == project.id, lastLoadedClipsHash == currentClipsHash {
            AppLogger.playback.debug("loadProject skipped - already loaded this exact project state")
            return
        }

        loadingTask?.cancel()

        // Short debounce for edits on the same project; longer when switching projects, to avoid thrash while browsing.
        let isSameProject = (lastLoadedProjectID == project.id)
        let debounceDelay: UInt64 = {
            if forceReload { return 0 }
            return isSameProject ? editDebounceDelay : projectSwitchDebounceDelay
        }()

        // Set duration from the timeline now so the UI responds while composition runs in the background.
        self.duration = project.timeline.duration
        self.pendingProject = project
        self.isCompositionReady = false
        self.isPreparingComposition = true

        lastLoadedProjectID = project.id
        lastLoadedClipsHash = currentClipsHash

        // Debounce composition: another load inside the window cancels this task.
        loadingTask = Task {
            if debounceDelay > 0 {
                try? await Task.sleep(nanoseconds: debounceDelay)
            }

            guard !Task.isCancelled else { return }

            do {
                let totalClips = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
                AppLogger.playback.debug("Composing player item for project: \(project.name) with \(totalClips) clips")
                let playerItem = try await ServiceContainer.shared.timelineEngine.composePlayerItem(for: project)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.unload()
                    self.setupPlayer(with: playerItem, duration: project.timeline.duration)
                    self.isCompositionReady = true
                    self.isPreparingComposition = false
                    self.pendingProject = nil
                    AppLogger.playback.info("Loaded project \(project.name)")
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isPreparingComposition = false
                }
                AppLogger.playback.error("Failed to compose project timeline: \(error)")
            }
        }
    }

    /// Force immediate composition (called when user clicks play on pending project)
    private func ensureCompositionReady() async {
        guard let project = pendingProject, !isCompositionReady else { return }

        loadingTask?.cancel()
        isPreparingComposition = true

        do {
            AppLogger.playback.debug("Immediate composition for play: \(project.name)")
            let playerItem = try await ServiceContainer.shared.timelineEngine.composePlayerItem(for: project)

            await MainActor.run {
                self.unload()
                self.setupPlayer(with: playerItem, duration: project.timeline.duration)
                self.isCompositionReady = true
                self.isPreparingComposition = false
                self.pendingProject = nil
            }
        } catch {
            isPreparingComposition = false
            AppLogger.playback.error("Failed to compose for play: \(error)")
        }
    }

    private func setupPlayer(with item: AVPlayerItem, duration: CMTime) {
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = 1.0
        player = newPlayer
        self.duration = duration

        tokenHolder.player = newPlayer

        // Playback uses composition audio only. RealTimeAudioProcessor also played it, which doubled the audio and caused desync.

        // 0.1 s (10 fps) UI updates feel smooth at half the cost of 0.05 s.
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        // Must use Task { @MainActor in } for Sendable closure
        let observer = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor in
                self.currentTime = time
            }
        }

        timeObserver = observer
        tokenHolder.observer = observer

        // Without this, isPlaying stays true and playhead stays at end when video finishes
        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    /// Handle natural end of playback - reset state for standard video player behavior
    private func handlePlaybackEnded() {
        isPlaying = false
        seek(to: .zero)
        AppLogger.playback.debug("Playback ended naturally - reset to start")
    }

    func unload() {
        loadingTask?.cancel()
        loadingTask = nil

        if let observer = playbackEndedObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndedObserver = nil
        }

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
            tokenHolder.observer = nil
        }
        player?.pause()
        player = nil
        tokenHolder.player = nil
        isPreparingComposition = false

        tokenHolder.stopAccessing()

        isPlaying = false
        currentTime = .zero
        duration = .zero
    }

    // MARK: - Controls

    func play() {
        guard let project = ServiceContainer.shared.appState.projectState.currentProject else {
            AppLogger.playback.warning("Cannot play: No project loaded")
            ServiceContainer.shared.toastManager.show("No project to play", type: .error)
            return
        }

        let hasClips = project.timeline.tracks.contains { !$0.clips.isEmpty }
        guard hasClips else {
            AppLogger.playback.warning("Cannot play: Empty timeline")
            ServiceContainer.shared.toastManager.show("Cannot play empty timeline. Add clips first.", type: .error)
            return
        }

        if !isCompositionReady && pendingProject != nil {
            Task {
                await ensureCompositionReady()
                await MainActor.run {
                    self.startPlayback()
                }
            }
            return
        }

        startPlayback()
    }

    private func startPlayback() {
        guard let player = player else { return }
        if player.currentTime() >= duration {
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: CMTime) {
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func rewind(by seconds: Double = 5.0) {
        guard duration.seconds > 0 else { return }
        let newTime = max(0, currentTime.seconds - seconds)
        seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }

    func forward(by seconds: Double = 5.0) {
        guard duration.seconds > 0 else { return }
        let newTime = min(duration.seconds, currentTime.seconds + seconds)
        seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }

    // MARK: - Frame Stepping (Arrow Keys)

    /// Get the actual frame rate from the current player item, with 30fps fallback
    private func getFrameRate() async -> Double {
        guard let playerItem = player?.currentItem,
              let asset = playerItem.asset as? AVURLAsset else {
            return 30.0 // Fallback for composition assets
        }

        do {
            let tracks = try await asset.load(.tracks)
            if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                if frameRate > 0 {
                    return Double(frameRate)
                }
            }
        } catch {
            AppLogger.playback.debug("Could not determine frame rate: \(error.localizedDescription)")
        }

        return 30.0 // Default fallback
    }

    /// Step forward one frame (uses actual video frame rate)
    func stepForward() {
        pause()
        Task {
            let frameRate = await getFrameRate()
            let frameDuration = 1.0 / frameRate
            let newTime = min(duration.seconds, currentTime.seconds + frameDuration)
            await MainActor.run {
                seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
            }
        }
    }

    /// Step backward one frame (uses actual video frame rate)
    func stepBackward() {
        pause()
        Task {
            let frameRate = await getFrameRate()
            let frameDuration = 1.0 / frameRate
            let newTime = max(0, currentTime.seconds - frameDuration)
            await MainActor.run {
                seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
            }
        }
    }

    /// Seek forward 10 seconds (Shift+Right Arrow)
    func seekForward10Seconds() {
        let newTime = min(duration.seconds, currentTime.seconds + 10.0)
        seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }

    /// Seek backward 10 seconds (Shift+Left Arrow)
    func seekBackward10Seconds() {
        let newTime = max(0, currentTime.seconds - 10.0)
        seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
    }

    // MARK: - Playback Rate Control (J/K/L Shuttle)

    /// Set playback rate for shuttle control (negative = reverse, >1 = fast forward)
    func setPlaybackRate(_ rate: Float) {
        guard let player = player else { return }

        if rate == 0 {
            pause()
        } else {
            // Seek requires pause first for reverse playback on some media
            if rate < 0, player.rate >= 0 {
                player.rate = rate
            } else {
                player.rate = rate
            }
            isPlaying = rate != 0
        }
    }
}
