//
//  FFmpegService.swift
//  SaneVideo
//
//  FFmpeg integration for advanced export operations
//

#if !APP_STORE
    @preconcurrency import AVFoundation
    import CoreMedia
    import Foundation

    /// Service for FFmpeg-based export operations
    actor FFmpegService {
        private let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

        init() {}

        /// Check if FFmpeg is installed
        var isAvailable: Bool {
            get async {
                FileManager.default.fileExists(atPath: ffmpegPath)
            }
        }

        // MARK: - GIF Export

        func exportAsGIF(
            inputURL: URL,
            outputURL: URL,
            fps: Int = 10,
            width: Int = 480,
            startTime: Double? = nil,
            duration: Double? = nil,
            progressHandler: (@Sendable (Double) -> Void)? = nil
        ) async throws {
            guard await isAvailable else {
                throw FFmpegError.notInstalled
            }

            var arguments: [String] = []
            if let start = startTime {
                arguments += ["-ss", String(format: "%.2f", start)]
            }
            arguments += ["-i", inputURL.path]
            if let dur = duration {
                arguments += ["-t", String(format: "%.2f", dur)]
            }
            let filter = "fps=\(fps),scale=\(width):-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
            arguments += ["-vf", filter]
            arguments += ["-loop", "0"]
            arguments += ["-y"]
            arguments += [outputURL.path]
            try await executeFFmpeg(arguments: arguments)
            progressHandler?(1.0)
        }

        // MARK: - Format Conversion

        func convert(
            inputURL: URL,
            outputURL: URL,
            codec: VideoCodec = .h264,
            preset: EncodingPreset = .fast
        ) async throws {
            guard await isAvailable else {
                throw FFmpegError.notInstalled
            }
            var arguments = ["-i", inputURL.path]
            arguments += ["-c:v", codec.ffmpegName]
            arguments += ["-preset", preset.rawValue]
            arguments += ["-c:a", "aac"]
            arguments += ["-y", outputURL.path]
            try await executeFFmpeg(arguments: arguments)
        }

        // MARK: - Sync Repair

        func inspectSync(inputURL: URL) async throws -> SyncInspection {
            let asset = AVURLAsset(url: inputURL)
            let duration = try await asset.load(.duration)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            var audioDurations: [Double] = []
            for track in audioTracks {
                let timeRange = try await track.load(.timeRange)
                audioDurations.append(max(0, timeRange.duration.seconds))
            }

            let videoDuration = max(0, duration.seconds)
            let primaryAudioDuration = audioDurations.first
            let detectedTailGap = max(0, videoDuration - (primaryAudioDuration ?? 0))

            let suggestedMarker: Double? = {
                guard let primaryAudioDuration, detectedTailGap > 0.25 else { return nil }
                let stretchWindow = max(10.0, min(60.0, detectedTailGap * 2.0))
                return max(0, primaryAudioDuration - stretchWindow)
            }()

            let suggestedTailTempo: Double? = {
                guard
                    let primaryAudioDuration,
                    let suggestedMarker,
                    videoDuration > suggestedMarker,
                    primaryAudioDuration > suggestedMarker
                else { return nil }

                let audioTail = primaryAudioDuration - suggestedMarker
                let videoTail = videoDuration - suggestedMarker
                guard audioTail > 0.01, videoTail > 0.01 else { return nil }
                return (audioTail / videoTail).clamped(to: 0.5 ... 2.0)
            }()

            return SyncInspection(
                videoDuration: videoDuration,
                audioDurations: audioDurations,
                primaryAudioDuration: primaryAudioDuration,
                detectedTailGap: detectedTailGap,
                suggestedMarker: suggestedMarker,
                suggestedTailTempo: suggestedTailTempo
            )
        }

        func suggestedSyncRepairOutputURL(inputURL: URL, mode: SyncRepairMode) -> URL {
            Self.makeSuggestedSyncRepairOutputURL(inputURL: inputURL, mode: mode)
        }

        func repairSync(
            inputURL: URL,
            outputURL: URL,
            mode: SyncRepairMode,
            markerTime: Double? = nil,
            offsetSeconds: Double = 0,
            tailTempo: Double = 1.0
        ) async throws {
            guard await isAvailable else {
                throw FFmpegError.notInstalled
            }

            let inspection = try await inspectSync(inputURL: inputURL)
            guard !inspection.audioDurations.isEmpty else {
                throw FFmpegError.invalidInput
            }

            let resolvedMarker = markerTime ?? inspection.suggestedMarker
            let request = SyncRepairBuildRequest(
                inputPath: inputURL.path,
                outputPath: outputURL.path,
                audioTrackCount: inspection.audioDurations.count,
                videoDuration: inspection.videoDuration,
                primaryAudioDuration: inspection.primaryAudioDuration,
                mode: mode,
                markerTime: resolvedMarker,
                offsetSeconds: offsetSeconds,
                tailTempo: tailTempo
            )
            let arguments = try Self.buildSyncRepairArguments(request: request)

            try await executeFFmpeg(arguments: arguments)
        }

        // MARK: - Helpers

        nonisolated static func makeSuggestedSyncRepairOutputURL(
            inputURL: URL,
            mode: SyncRepairMode,
            fileManager: FileManager = .default
        ) -> URL {
            let directory = inputURL.deletingLastPathComponent()
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let ext = "mp4"
            let stem = "\(baseName)_\(mode.fileSuffix)"
            var candidate = directory.appendingPathComponent("\(stem).\(ext)")
            var counter = 2

            while fileManager.fileExists(atPath: candidate.path) {
                candidate = directory.appendingPathComponent("\(stem)_\(counter).\(ext)")
                counter += 1
            }

            return candidate
        }

        nonisolated static func buildSyncRepairArguments(request: SyncRepairBuildRequest) throws -> [String] {
            guard request.audioTrackCount > 0, request.videoDuration > 0 else {
                throw FFmpegError.invalidInput
            }

            var arguments = ["-hide_banner", "-i", request.inputPath]

            switch request.mode {
            case .shiftWholeTrack:
                let filter = buildGlobalShiftFilter(
                    audioTrackCount: request.audioTrackCount,
                    offsetSeconds: request.offsetSeconds
                )
                arguments += ["-filter_complex", filter]
                arguments += buildFilteredOutputMaps(audioTrackCount: request.audioTrackCount)
                arguments += commonFilteredOutputArguments(
                    videoDuration: request.videoDuration,
                    outputPath: request.outputPath
                )

            case .shiftFromMarker:
                guard let rawMarker = request.markerTime else {
                    throw FFmpegError.invalidInput
                }
                let marker = validatedMarker(rawMarker, within: request.videoDuration)
                let filter = buildTailShiftFilter(
                    audioTrackCount: request.audioTrackCount,
                    markerTime: marker,
                    offsetSeconds: request.offsetSeconds
                )
                arguments += ["-filter_complex", filter]
                arguments += buildFilteredOutputMaps(audioTrackCount: request.audioTrackCount)
                arguments += commonFilteredOutputArguments(
                    videoDuration: request.videoDuration,
                    outputPath: request.outputPath
                )

            case .stretchTailFromMarker:
                guard let rawMarker = request.markerTime else {
                    throw FFmpegError.invalidInput
                }
                let marker = validatedMarker(rawMarker, within: request.videoDuration)
                let filter = buildTailStretchFilter(
                    audioTrackCount: request.audioTrackCount,
                    markerTime: marker,
                    tailTempo: request.tailTempo.clamped(to: 0.5 ... 2.0)
                )
                arguments += ["-filter_complex", filter]
                arguments += buildFilteredOutputMaps(audioTrackCount: request.audioTrackCount)
                arguments += commonFilteredOutputArguments(
                    videoDuration: request.videoDuration,
                    outputPath: request.outputPath
                )

            case .trimVideoToPrimaryAudio:
                guard let primaryAudioDuration = request.primaryAudioDuration, primaryAudioDuration > 0 else {
                    throw FFmpegError.invalidInput
                }
                arguments += [
                    "-map", "0:v:0",
                    "-map", "0:a?",
                    "-t", formatSeconds(min(request.videoDuration, primaryAudioDuration)),
                    "-c", "copy",
                    "-movflags", "+faststart",
                    "-y", request.outputPath
                ]

            case .padAudioToVideoEnd:
                let filter = buildPadAudioFilter(
                    audioTrackCount: request.audioTrackCount,
                    videoDuration: request.videoDuration
                )
                arguments += ["-filter_complex", filter]
                arguments += buildFilteredOutputMaps(audioTrackCount: request.audioTrackCount)
                arguments += commonFilteredOutputArguments(
                    videoDuration: request.videoDuration,
                    outputPath: request.outputPath
                )
            }

            return arguments
        }

        private nonisolated static func buildFilteredOutputMaps(audioTrackCount: Int) -> [String] {
            var maps = ["-map", "0:v:0"]
            for index in 0 ..< audioTrackCount {
                maps += ["-map", "[a\(index)]"]
            }
            return maps
        }

        private nonisolated static func commonFilteredOutputArguments(
            videoDuration: Double,
            outputPath: String
        ) -> [String] {
            [
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "192k",
                "-t", formatSeconds(videoDuration),
                "-movflags", "+faststart",
                "-y", outputPath
            ]
        }

        private nonisolated static func validatedMarker(_ markerTime: Double, within videoDuration: Double) -> Double {
            max(0.05, min(markerTime, max(0.10, videoDuration - 0.05)))
        }

        private nonisolated static func buildGlobalShiftFilter(
            audioTrackCount: Int,
            offsetSeconds: Double
        ) -> String {
            let delayMilliseconds = max(0, Int((offsetSeconds * 1000).rounded()))
            let advanceSeconds = max(0, -offsetSeconds)

            return (0 ..< audioTrackCount).map { index in
                if offsetSeconds >= 0 {
                    return "[0:a:\(index)]adelay=\(delayMilliseconds):all=1,aresample=async=1:first_pts=0[a\(index)]"
                }

                return "[0:a:\(index)]atrim=start=\(formatSeconds(advanceSeconds)),asetpts=PTS-STARTPTS,aresample=async=1:first_pts=0[a\(index)]"
            }
            .joined(separator: ";")
        }

        private nonisolated static func buildTailShiftFilter(
            audioTrackCount: Int,
            markerTime: Double,
            offsetSeconds: Double
        ) -> String {
            let delayMilliseconds = max(0, Int((offsetSeconds * 1000).rounded()))
            let advanceSeconds = max(0, -offsetSeconds)

            return (0 ..< audioTrackCount).map { index in
                let prefix = "[0:a:\(index)]asplit=2[preRaw\(index)][postRaw\(index)];" +
                    "[preRaw\(index)]atrim=0:\(formatSeconds(markerTime)),asetpts=PTS-STARTPTS[pre\(index)];"

                let postOperation: String
                if offsetSeconds >= 0 {
                    postOperation = "[postRaw\(index)]atrim=start=\(formatSeconds(markerTime)),asetpts=PTS-STARTPTS,adelay=\(delayMilliseconds):all=1[post\(index)]"
                } else {
                    postOperation = "[postRaw\(index)]atrim=start=\(formatSeconds(markerTime + advanceSeconds)),asetpts=PTS-STARTPTS[post\(index)]"
                }

                let suffix = "[pre\(index)][post\(index)]concat=n=2:v=0:a=1,aresample=async=1:first_pts=0[a\(index)]"
                return prefix + postOperation + ";" + suffix
            }
            .joined(separator: ";")
        }

        private nonisolated static func buildTailStretchFilter(
            audioTrackCount: Int,
            markerTime: Double,
            tailTempo: Double
        ) -> String {
            let atempo = atempoFilter(for: tailTempo)

            return (0 ..< audioTrackCount).map { index in
                "[0:a:\(index)]asplit=2[preRaw\(index)][postRaw\(index)];" +
                    "[preRaw\(index)]atrim=0:\(formatSeconds(markerTime)),asetpts=PTS-STARTPTS[pre\(index)];" +
                    "[postRaw\(index)]atrim=start=\(formatSeconds(markerTime)),asetpts=PTS-STARTPTS,\(atempo)[post\(index)];" +
                    "[pre\(index)][post\(index)]concat=n=2:v=0:a=1,aresample=async=1:first_pts=0[a\(index)]"
            }
            .joined(separator: ";")
        }

        private nonisolated static func buildPadAudioFilter(
            audioTrackCount: Int,
            videoDuration: Double
        ) -> String {
            (0 ..< audioTrackCount).map { index in
                "[0:a:\(index)]apad=whole_dur=\(formatSeconds(videoDuration)),aresample=async=1:first_pts=0[a\(index)]"
            }
            .joined(separator: ";")
        }

        private nonisolated static func atempoFilter(for value: Double) -> String {
            var remaining = value
            var filters: [String] = []

            while remaining > 2.0 {
                filters.append("atempo=2.0")
                remaining /= 2.0
            }

            while remaining < 0.5 {
                filters.append("atempo=0.5")
                remaining /= 0.5
            }

            filters.append("atempo=\(formatSeconds(remaining))")
            return filters.joined(separator: ",")
        }

        private nonisolated static func formatSeconds(_ value: Double) -> String {
            String(format: "%.3f", value)
        }

        // MARK: - Private

        private func executeFFmpeg(arguments: [String]) async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = arguments

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: FFmpegError.executionFailed(errorMessage))
                    }
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: FFmpegError.executionFailed(error.localizedDescription))
                }
            }
        }
    }
#else
    import AVFoundation
    import CoreMedia
    import Foundation

    /// No-op stub — FFmpeg uses Process() which is not allowed in App Store sandbox.
    actor FFmpegService {
        init() {}

        var isAvailable: Bool {
            get async { false }
        }

        func exportAsGIF(
            inputURL _: URL,
            outputURL _: URL,
            fps _: Int = 10,
            width _: Int = 480,
            startTime _: Double? = nil,
            duration _: Double? = nil,
            progressHandler _: (@Sendable (Double) -> Void)? = nil
        ) async throws {
            throw FFmpegError.notInstalled
        }

        func convert(
            inputURL _: URL,
            outputURL _: URL,
            codec _: VideoCodec = .h264,
            preset _: EncodingPreset = .fast
        ) async throws {
            throw FFmpegError.notInstalled
        }

        func inspectSync(inputURL _: URL) async throws -> SyncInspection {
            throw FFmpegError.notInstalled
        }

        func suggestedSyncRepairOutputURL(inputURL: URL, mode: SyncRepairMode) -> URL {
            let directory = inputURL.deletingLastPathComponent()
            let stem = "\(inputURL.deletingPathExtension().lastPathComponent)_\(mode.fileSuffix)"
            return directory.appendingPathComponent("\(stem).mp4")
        }

        func repairSync(
            inputURL _: URL,
            outputURL _: URL,
            mode _: SyncRepairMode,
            markerTime _: Double? = nil,
            offsetSeconds _: Double = 0,
            tailTempo _: Double = 1.0
        ) async throws {
            throw FFmpegError.notInstalled
        }
    }
#endif

// MARK: - Types

enum FFmpegError: Error, LocalizedError {
    case notInstalled
    case executionFailed(String)
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "FFmpeg is not installed. Install via: brew install ffmpeg"
        case let .executionFailed(message):
            "FFmpeg failed: \(message)"
        case .invalidInput:
            "Invalid input file"
        }
    }
}

enum VideoCodec: String, CaseIterable {
    case h264 = "H.264"
    case h265 = "H.265 (HEVC)"
    case prores = "ProRes"

    var ffmpegName: String {
        switch self {
        case .h264: "libx264"
        case .h265: "libx265"
        case .prores: "prores_ks"
        }
    }
}

enum EncodingPreset: String, CaseIterable {
    case ultrafast
    case fast
    case medium
    case slow
    case veryslow
}

struct SyncInspection: Equatable, Sendable {
    let videoDuration: Double
    let audioDurations: [Double]
    let primaryAudioDuration: Double?
    let detectedTailGap: Double
    let suggestedMarker: Double?
    let suggestedTailTempo: Double?
}

struct SyncRepairBuildRequest: Equatable, Sendable {
    let inputPath: String
    let outputPath: String
    let audioTrackCount: Int
    let videoDuration: Double
    let primaryAudioDuration: Double?
    let mode: SyncRepairMode
    let markerTime: Double?
    let offsetSeconds: Double
    let tailTempo: Double
}

enum SyncRepairMode: String, CaseIterable, Identifiable, Sendable {
    case shiftWholeTrack
    case shiftFromMarker
    case stretchTailFromMarker
    case trimVideoToPrimaryAudio
    case padAudioToVideoEnd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shiftWholeTrack:
            "Shift Entire Audio"
        case .shiftFromMarker:
            "Shift Tail From Marker"
        case .stretchTailFromMarker:
            "Stretch Tail To Fit"
        case .trimVideoToPrimaryAudio:
            "Trim Video To Audio End"
        case .padAudioToVideoEnd:
            "Pad Audio To Video End"
        }
    }

    var subtitle: String {
        switch self {
        case .shiftWholeTrack:
            "Move every audio track earlier or later against the existing picture."
        case .shiftFromMarker:
            "Keep the opening in place and only offset the section after a marker."
        case .stretchTailFromMarker:
            "Speed up or slow down the audio tail after a marker."
        case .trimVideoToPrimaryAudio:
            "Drop the broken picture tail once the main audio has already ended."
        case .padAudioToVideoEnd:
            "Fill the gap with silence so the clip keeps the same picture length."
        }
    }

    var fileSuffix: String {
        switch self {
        case .shiftWholeTrack:
            "sync_shifted"
        case .shiftFromMarker:
            "sync_shifted_tail"
        case .stretchTailFromMarker:
            "sync_stretched_tail"
        case .trimVideoToPrimaryAudio:
            "sync_trimmed"
        case .padAudioToVideoEnd:
            "sync_padded"
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
