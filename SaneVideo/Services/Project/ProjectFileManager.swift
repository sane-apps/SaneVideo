//
//  ProjectFileManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Foundation

/// Centralized service for handling File IO, Bookmark Resolution, and Asset Loading
/// Replaces ad-hoc IO in VideoClip and ProjectState
final class ProjectFileManager: Sendable {

    init() {}

    // MARK: - Asset Loading

    /// Load a video clip from a URL, handling security scope and async duration loading
    func loadClip(from url: URL) async throws -> VideoClip {
        // 1. Access security scoped resource if needed
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // 2. Load duration with RETRY mechanism
        // The file might be busy being written to disk by the screen recorder
        var duration: CMTime = .zero
        var lastError: Error?
        
        let options = [AVURLAssetPreferPreciseDurationAndTimingKey: true]

        for attempt in 1...3 {
            do {
                let asset = AVURLAsset(url: url, options: options)
                duration = try await asset.load(.duration)
                
                // If we get here, it worked
                lastError = nil
                
                // 3. Log metadata
                await logVideoMetadata(asset: asset, filename: url.lastPathComponent)
                break
            } catch {
                lastError = error
                AppLogger.project.warning("Attempt \(attempt) to load asset duration failed: \(error.localizedDescription)")
                // Exponential backoff: 0.2s, 0.4s, 0.8s
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 100_000_000))
            }
        }

        if let error = lastError {
            throw error
        }
        
        // 4. Create Bookmark (Off Main Thread)
        // Use a local capture to avoid actor isolation issues
        let bookmarkData = try? await Task.detached(priority: .utility) {
            // Create bookmark directly - not MainActor isolated
            try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }.value

        // 5. Create Clip
        return VideoClip(
            url: url,
            duration: duration,
            bookmarkData: bookmarkData
        )
    }

    // MARK: - Video Quality Detection

    /// Detects and logs video resolution, framerate, codec, and quality tier
    private func logVideoMetadata(asset: AVURLAsset, filename: String) async {
        do {
            guard let videoTrack = try await asset.load(.tracks).first(where: { $0.mediaType == .video }) else {
                AppLogger.project.warning("⚠️ No video track found in: \(filename)")
                return
            }

            let naturalSize = try await videoTrack.load(.naturalSize)
            let frameRate = try await videoTrack.load(.nominalFrameRate)
            let transform = try await videoTrack.load(.preferredTransform)

            // Calculate actual dimensions (accounting for rotation)
            let isRotated = transform.b != 0 || transform.c != 0
            let width = isRotated ? naturalSize.height : naturalSize.width
            let height = isRotated ? naturalSize.width : naturalSize.height

            // Determine quality tier
            let qualityTier = detectQualityTier(width: width, height: height)

            // Get codec info (format description)
            var codecName = "Unknown"
            if let formatDescriptions = try? await videoTrack.load(.formatDescriptions),
               let formatDesc = formatDescriptions.first {
                let fourCC = CMFormatDescriptionGetMediaSubType(formatDesc)
                codecName = fourCCToString(fourCC)
            }

            // Get file size
            let fileSize = getFileSize(url: asset.url)
            let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

            // Log comprehensive info
            AppLogger.project.info("""
            📹 Video Imported: \(filename)
               Resolution: \(Int(width))×\(Int(height)) (\(qualityTier.name))
               Frame Rate: \(String(format: "%.2f", frameRate)) fps
               Codec: \(codecName)
               File Size: \(fileSizeStr)
               Est. Memory: \(qualityTier.estimatedMemoryMB)MB per frame buffer
            """)

            // Show toast for high-res videos (user awareness)
            if qualityTier.isHighRes {
                await MainActor.run {
                    ServiceContainer.shared.toastManager.show("📹 \(qualityTier.name) video (\(Int(width))×\(Int(height)))")
                }
            }

        } catch {
            AppLogger.project.warning("⚠️ Could not read video metadata: \(error.localizedDescription)")
        }
    }

    /// Quality tier enumeration with memory estimates
    private struct QualityTier {
        let name: String
        let isHighRes: Bool
        let estimatedMemoryMB: Int
    }

    private func detectQualityTier(width: CGFloat, height: CGFloat) -> QualityTier {
        let pixels = width * height

        switch pixels {
        case _ where pixels >= 8_294_400: // 3840×2160 or higher
            return QualityTier(name: "4K UHD", isHighRes: true, estimatedMemoryMB: 32)
        case _ where pixels >= 3_686_400: // 2560×1440
            return QualityTier(name: "1440p QHD", isHighRes: true, estimatedMemoryMB: 15)
        case _ where pixels >= 2_073_600: // 1920×1080
            return QualityTier(name: "1080p HD", isHighRes: false, estimatedMemoryMB: 8)
        case _ where pixels >= 921_600: // 1280×720
            return QualityTier(name: "720p HD", isHighRes: false, estimatedMemoryMB: 4)
        case _ where pixels >= 409_920: // 854×480
            return QualityTier(name: "480p SD", isHighRes: false, estimatedMemoryMB: 2)
        default:
            return QualityTier(name: "Low-res", isHighRes: false, estimatedMemoryMB: 1)
        }
    }

    private func fourCCToString(_ fourCC: FourCharCode) -> String {
        let bytes = [
            UInt8((fourCC >> 24) & 0xFF),
            UInt8((fourCC >> 16) & 0xFF),
            UInt8((fourCC >> 8) & 0xFF),
            UInt8(fourCC & 0xFF)
        ]
        if let str = String(bytes: bytes, encoding: .ascii) {
            return str.trimmingCharacters(in: .whitespaces)
        }
        return String(format: "0x%08X", fourCC)
    }

    private func getFileSize(url: URL) -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return attrs[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Bookmarks

    /// Creates a security-scoped bookmark for a URL
    /// Note: This is nonisolated and can be called from any context
    nonisolated func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a bookmark to a URL, handling staleness
    func resolveBookmark(data: Data) throws -> (URL, Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    // MARK: - File Management

    func deleteFile(at url: URL) async throws {
        // Run on background thread to avoid blocking MainActor callers
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        }.value
    }

    // MARK: - Project Hydration

    /// Resolves bookmarks for all clips in a project, updating URLs if needed
    func hydrateProject(_ project: VideoProject) -> VideoProject {
        var updatedProject = project
        var updatedTracks: [Track] = []

        for var track in project.timeline.tracks {
            var updatedClips: [VideoClip] = []

            for var clip in track.clips {
                if let bookmarkData = clip.bookmarkData {
                    do {
                        let (resolvedURL, isStale) = try resolveBookmark(data: bookmarkData)

                        if isStale {
                            // Update bookmark if stale
                            if let newBookmark = try? createBookmark(for: resolvedURL) {
                                clip.bookmarkData = newBookmark
                            }
                        }

                        // Check if file moved
                        if clip.url != resolvedURL {
                            print("ProjectFileManager: Resolved moved file: \(clip.url.lastPathComponent) -> \(resolvedURL.path)")
                            // Update URL
                            clip.url = resolvedURL
                        }
                        
                        // Check existence
                        if !FileManager.default.fileExists(atPath: resolvedURL.path) {
                            print("ProjectFileManager: File missing at \(resolvedURL.path)")
                            clip.isMissing = true
                        } else {
                            clip.isMissing = false
                        }
                        
                        updatedClips.append(clip)

                    } catch {
                        print("ProjectFileManager: Failed to resolve bookmark for \(clip.url.lastPathComponent): \(error)")
                        AppLogger.project.warning("Failed to resolve bookmark for \(clip.url.lastPathComponent): \(error)")
                        
                        // Mark as missing if we can't resolve
                        clip.isMissing = true
                        updatedClips.append(clip) 
                    }
                } else {
                    // No bookmark - check if file exists at original URL (unlikely for sandboxed app but possible for temp files)
                    if !FileManager.default.fileExists(atPath: clip.url.path) {
                        clip.isMissing = true
                    } else {
                        clip.isMissing = false
                    }
                    updatedClips.append(clip)
                }
            }

            track.clips = updatedClips
            updatedTracks.append(track)
        }

        updatedProject.timeline.tracks = updatedTracks
        return updatedProject
    }

    // MARK: - Security Scope Session

    /// A session that manages the lifecycle of multiple security-scoped resource accesses
    final class SecurityScopeSession: Sendable {
        private let urls: [URL]
        private let activeURLs: [URL]

        init(urls: [URL]) {
            self.urls = urls
            var accessed: [URL] = []
            for url in urls where url.startAccessingSecurityScopedResource() {
                accessed.append(url)
            }
            self.activeURLs = accessed
            AppLogger.project.info("🔐 Started security scope session for \(accessed.count)/\(urls.count) URLs")
        }

        deinit {
            stop()
        }

        func stop() {
            for url in activeURLs {
                url.stopAccessingSecurityScopedResource()
            }
            AppLogger.project.info("🔓 Stopped security scope session for \(activeURLs.count) URLs")
        }
    }

    /// Enters security scope for all media in a project
    func enterSecurityScope(for project: VideoProject) -> SecurityScopeSession {
        var urls: Set<URL> = []
        for track in project.timeline.tracks {
            for clip in track.clips {
                urls.insert(clip.url)
                if let cursorURL = clip.cursorDataURL {
                    urls.insert(cursorURL)
                }
                if let clickURL = clip.clickDataURL {
                    urls.insert(clickURL)
                }
                if let enhancedURL = clip.enhancedAudioURL {
                    urls.insert(enhancedURL)
                }
            }
        }
        return SecurityScopeSession(urls: Array(urls))
    }
}
