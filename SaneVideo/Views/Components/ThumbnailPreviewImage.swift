// Shows a static thumbnail instead of an AVPlayer until playback starts, so project switching is instant.

import AVFoundation
import SwiftUI

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
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white.opacity(0.5))
                    }
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "film")
                                .font(.system(size: 40))
                                .foregroundColor(Color.stone)
                            Text(clip.url.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(Color.stone)
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

        // Wide tolerances let the generator use the nearest keyframe, which is fast.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

        // 2x for Retina.
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
