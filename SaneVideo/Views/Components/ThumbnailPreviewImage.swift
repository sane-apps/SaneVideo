//
//  ThumbnailPreviewImage.swift
//  SaneVideo
//
//  PERFORMANCE: Static thumbnail for instant project switching
//  Shows a thumbnail instead of AVPlayer until playback starts
//

import AVFoundation
import SwiftUI

/// Displays a thumbnail image from a video clip
/// Used for instant project preview without creating an AVPlayer
struct ThumbnailPreviewImage: View {
    let clip: VideoClip
    let size: CGSize

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                // Placeholder while loading
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white.opacity(0.5))
                    }
            } else {
                // Failed to load - show placeholder
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "film")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text(clip.url.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: clip.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true

        // PERFORMANCE: Use wide tolerances for fast iFrame lookup
        // This lets AVAssetImageGenerator pick the nearest keyframe
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

        // Request appropriate size for display (2x for retina)
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)

        // Get thumbnail at 25% into the clip (more interesting than first frame)
        let time = CMTime(seconds: clip.effectiveDuration.seconds * 0.25, preferredTimescale: 600)
        let originalTime = clip.originalTime(forEffectiveTime: time) ?? clip.trimStart

        do {
            let result = try await generator.image(at: originalTime)
            let nsImage = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))

            await MainActor.run {
                self.thumbnail = nsImage
                self.isLoading = false
            }
        } catch {
            AppLogger.general.warning("Thumbnail generation failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
