//
//  FFmpegService.swift
//  SaneVideo
//
//  FFmpeg integration for advanced export operations
//

import Foundation
import CoreMedia

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
    
    /// Export a video clip as an animated GIF
    /// - Parameters:
    ///   - inputURL: Source video file
    ///   - outputURL: Destination GIF file
    ///   - fps: Frames per second (default 10)
    ///   - width: Output width (default 480, height auto-calculated)
    ///   - startTime: Optional start time in seconds
    ///   - duration: Optional duration in seconds
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
        
        // Build FFmpeg arguments
        var arguments: [String] = []
        
        // Input options
        if let start = startTime {
            arguments += ["-ss", String(format: "%.2f", start)]
        }
        
        arguments += ["-i", inputURL.path]
        
        if let dur = duration {
            arguments += ["-t", String(format: "%.2f", dur)]
        }
        
        // Video filter for GIF conversion
        // Uses palettegen + paletteuse for high quality
        let filter = "fps=\(fps),scale=\(width):-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
        arguments += ["-vf", filter]
        
        // Output options
        arguments += ["-loop", "0"] // Infinite loop
        arguments += ["-y"] // Overwrite output
        arguments += [outputURL.path]
        
        // Execute FFmpeg
        try await executeFFmpeg(arguments: arguments)
        
        progressHandler?(1.0)
    }
    
    // MARK: - Format Conversion
    
    /// Convert video to different format
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
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw FFmpegError.executionFailed(errorMessage)
            }
        } catch let error as FFmpegError {
            throw error
        } catch {
            throw FFmpegError.executionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Types

enum FFmpegError: Error, LocalizedError {
    case notInstalled
    case executionFailed(String)
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "FFmpeg is not installed. Install via: brew install ffmpeg"
        case .executionFailed(let message):
            return "FFmpeg failed: \(message)"
        case .invalidInput:
            return "Invalid input file"
        }
    }
}

enum VideoCodec: String, CaseIterable {
    case h264 = "H.264"
    case h265 = "H.265 (HEVC)"
    case prores = "ProRes"
    
    var ffmpegName: String {
        switch self {
        case .h264: return "libx264"
        case .h265: return "libx265"
        case .prores: return "prores_ks"
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
