//
//  PlaybackState.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

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

    // MARK: - In/Out Points (for selection range)

    /// In point marker for timeline selection (nil = not set)
    var inPoint: CMTime?

    /// Out point marker for timeline selection (nil = not set)
    var outPoint: CMTime?

    /// Clears both in and out points
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
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    // Helper for safe cleanup of player resources AND security scope
    // Note: This is a plain class (not MainActor) because deinit must be nonisolated
    private class TokenHolder {
        weak var player: AVPlayer?
        var observer: Any?

        // CRITICAL FIX: Hold security-scoped resource access for duration of playback
        // Without this, playback of files from Downloads/external drives may fail
        private var accessedURL: URL?

        func startAccessing(_ url: URL) {
            // Stop any previous access
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
            // Inline the security scope release to avoid actor isolation issues
            // stopAccessingSecurityScopedResource is thread-safe
            if let url = accessedURL {
                url.stopAccessingSecurityScopedResource()
            }
            if let observer, let player {
                player.removeTimeObserver(observer)
            }
        }
    }

    private var tokenHolder = TokenHolder()

    // CRITICAL FIX: Cancel loading task on deallocation
    // Task.cancel() is thread-safe, so we can call it from any thread in deinit
    // TokenHolder handles observer cleanup via its own deinit
    deinit {
        loadingTask?.cancel()
    }

    private func setupAudioSession() {
        // Ensure audio plays even if silent switch is on (iOS) or backgrounded
        // Less critical for macOS but good practice
    }

    // MARK: - Player Management

    func loadClip(_ clip: VideoClip) {
        // Cleanup old player (also releases previous security scope)
        unload()

        // CRITICAL FIX: Hold security scope for duration of playback
        // TokenHolder will release it when we unload or load a new clip
        tokenHolder.startAccessing(clip.url)

        let playerItem = AVPlayerItem(url: clip.url)
        setupPlayer(with: playerItem, duration: clip.duration)

        AppLogger.playback.info("Loaded clip \(clip.url.lastPathComponent)")
    }

    // Debounce properties to avoid double-loading
    // CRITICAL: Track clip IDs, not just count, to detect when clips change
    private var lastLoadedProjectID: UUID?
    private var lastLoadedClipsHash: Int = 0

    // CRITICAL FIX: Track loading task for cancellation on rapid reload
    // nonisolated(unsafe) required for deinit access from any thread
    @ObservationIgnored nonisolated(unsafe) private var loadingTask: Task<Void, Never>?

    // PERFORMANCE: Deferred loading - store pending project for lazy composition
    private var pendingProject: VideoProject?
    private var isCompositionReady: Bool = false

    // PERFORMANCE: Debounce delay for project switching (ms)
    private let compositionDebounceDelay: UInt64 = 300_000_000 // 300ms

    /// Reset playback state - call when switching projects
    func reset() {
        loadingTask?.cancel()
        loadingTask = nil
        pendingProject = nil
        isCompositionReady = false
        unload()
        lastLoadedProjectID = nil
        lastLoadedClipsHash = 0
        AppLogger.playback.debug("PlaybackState reset")
    }

    func loadProject(_ project: VideoProject, forceReload: Bool = false) {
        // GUARD: Don't try to compose empty timelines - causes freeze
        let hasClips = project.timeline.tracks.contains { !$0.clips.isEmpty }
        guard hasClips else {
            AppLogger.playback.debug("loadProject called with empty timeline - skipping composition")
            unload()
            pendingProject = nil
            isCompositionReady = false
            return
        }

        // Compute hash of clip IDs to detect actual content changes
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

        // DEBOUNCE: Skip if we just loaded this exact same project with same clips
        if !forceReload, lastLoadedProjectID == project.id, lastLoadedClipsHash == currentClipsHash {
            AppLogger.playback.debug("loadProject skipped - already loaded this exact project state")
            return
        }

        // Cancel any in-progress loading
        loadingTask?.cancel()

        // PERFORMANCE: Set duration immediately from timeline (no composition needed)
        // This makes the UI responsive while composition happens in background
        self.duration = project.timeline.duration
        self.pendingProject = project
        self.isCompositionReady = false

        // Update tracking
        lastLoadedProjectID = project.id
        lastLoadedClipsHash = currentClipsHash

        // PERFORMANCE: Debounced composition - wait for user to stop clicking
        // If user clicks another project within 300ms, this task gets cancelled
        loadingTask = Task {
            // Wait for debounce period
            try? await Task.sleep(nanoseconds: compositionDebounceDelay)

            // Check if cancelled during debounce
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
                    self.pendingProject = nil
                    AppLogger.playback.info("Loaded project \(project.name)")
                }
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.playback.error("Failed to compose project timeline: \(error)")
            }
        }
    }

    /// Force immediate composition (called when user clicks play on pending project)
    private func ensureCompositionReady() async {
        guard let project = pendingProject, !isCompositionReady else { return }

        // Cancel debounced task and compose immediately
        loadingTask?.cancel()

        do {
            AppLogger.playback.debug("Immediate composition for play: \(project.name)")
            let playerItem = try await ServiceContainer.shared.timelineEngine.composePlayerItem(for: project)

            await MainActor.run {
                self.unload()
                self.setupPlayer(with: playerItem, duration: project.timeline.duration)
                self.isCompositionReady = true
                self.pendingProject = nil
            }
        } catch {
            AppLogger.playback.error("Failed to compose for play: \(error)")
        }
    }

    private func setupPlayer(with item: AVPlayerItem, duration: CMTime) {
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        self.duration = duration

        // Update token holder
        tokenHolder.player = newPlayer

        // Setup real-time audio processing for instant effects
        // Get the current clip from the project to setup audio effects
        Task {
            if let project = ServiceContainer.shared.appState.projectState.currentProject {
                // Find the first clip that's currently playing (or first clip if none playing)
                let clips = project.timeline.tracks.flatMap { $0.clips }
                if let clip = clips.first {
                    do {
                        try await ServiceContainer.shared.realTimeAudioProcessor.setupForPlayerItem(
                            item,
                            clip: clip,
                            videoPlayer: newPlayer
                        )
                    } catch {
                        AppLogger.audio.warning("Failed to setup real-time audio processing: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Add time observer
        // PERFORMANCE: Use 0.1s interval (10fps) instead of 0.05s (20fps) for UI updates
        // This reduces update frequency by 50% while maintaining smooth playback feel
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        // CRITICAL FIX: Must use Task { @MainActor in } for Sendable closure
        let observer = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] time in
            guard let self = self else { return }
            // Update via MainActor task to satisfy Sendable closure requirements
            Task { @MainActor in
                self.currentTime = time
            }
        }

        timeObserver = observer
        tokenHolder.observer = observer
    }

    func unload() {
        // CRITICAL FIX: Cancel loading task before unloading
        loadingTask?.cancel()
        loadingTask = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
            tokenHolder.observer = nil
        }
        player?.pause()
        ServiceContainer.shared.realTimeAudioProcessor.cleanup()
        player = nil
        tokenHolder.player = nil

        // CRITICAL FIX: Release security-scoped resource access
        tokenHolder.stopAccessing()

        isPlaying = false
        currentTime = .zero
        duration = .zero
    }

    // MARK: - Controls

    func play() {
        // CRITICAL FIX: Validate timeline is not empty before play
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

        // PERFORMANCE: If composition isn't ready yet, wait for it
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
        ServiceContainer.shared.realTimeAudioProcessor.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        ServiceContainer.shared.realTimeAudioProcessor.pause()
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
        ServiceContainer.shared.realTimeAudioProcessor.seek(to: time)
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
                // Going from forward/pause to reverse
                player.rate = rate
            } else {
                player.rate = rate
            }
            isPlaying = rate != 0
        }
    }
}
