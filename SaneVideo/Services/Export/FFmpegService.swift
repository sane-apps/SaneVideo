//
//  FFmpegService.swift
//  SaneVideo
//
//  FFmpeg integration for advanced export operations
//

#if !APP_STORE
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

        // MARK: - Private

        private func executeFFmpeg(arguments: [String]) async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = arguments

            let errorPipe = Pipe()
            process.standardError = errorPipe

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
