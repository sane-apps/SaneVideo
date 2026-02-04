//
//  EditorLayoutView+VideoViews.swift
//  SaneVideo
//
//  Extracted from EditorLayoutView.swift to reduce file size
//  Contains: Video preview views and empty state
//

import AVFoundation
import CoreMedia
import SwiftUI

// MARK: - Magic Fix Empty State

struct EditorEmptyStateView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(Color.stone)

            VStack(spacing: 12) {
                Text("Let's Make Some Magic")
                    .font(.system(size: 28, weight: .bold))

                Text(String(localized: "editor.empty.subtitle", defaultValue: "Drop a video here or record to see the magic."))
                    .font(.system(size: 15))
                    .foregroundColor(Color.stone)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button(
                action: onImport,
                label: {
                    Label("Import Your First Video", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            )
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
        }
    }
}

// MARK: - Video Size Calculator

enum VideoSizeCalculator {
    /// Calculate optimal video size to fill available space while maintaining 16:9 aspect ratio
    static func calculateVideoSize(availableSize: CGSize) -> CGSize {
        let videoAspect: CGFloat = 16.0 / 9.0
        let containerAspect = availableSize.width / availableSize.height

        // Video size calculation: fit 16:9 video into available space with minimal padding
        let padding: CGFloat = 16 // Total padding (8 per side)
        let usableWidth = availableSize.width - padding
        let usableHeight = availableSize.height - padding

        if containerAspect > videoAspect {
            // Container is wider than video - height constrained
            let height = usableHeight
            let width = height * videoAspect
            return CGSize(width: width, height: height)
        } else {
            // Container is taller than video - width constrained
            let width = usableWidth
            let height = width / videoAspect
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - Thumbnail Preview View

struct EditorThumbnailPreviewView: View {
    let project: VideoProject
    let availableSize: CGSize
    let selectedClip: VideoClip?
    let currentTime: CMTime
    let onPlay: () -> Void
    let isPlayerReady: Bool
    let captionData: (Caption, CMTime)?

    var body: some View {
        let videoSize = VideoSizeCalculator.calculateVideoSize(availableSize: availableSize)

        ZStack {
            // Background
            Color.black

            // Show thumbnail from first clip
            if let firstClip = project.timeline.tracks.flatMap({ $0.clips }).first {
                ThumbnailPreviewImage(clip: firstClip, size: videoSize)
            }

            // Play button overlay
            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 80, height: 80)

                    Image(systemName: "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .opacity(isPlayerReady ? 0.7 : 0.9)

            // Loading indicator if composition is in progress
            if !isPlayerReady {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 16)
                }
            }

            // Caption overlay (if applicable)
            if let captionData = captionData {
                CaptionOverlayView(
                    caption: captionData.0,
                    currentTime: captionData.1,
                    style: project.captionStyle,
                    offset: .constant(project.captionOffset)
                )
            }
        }
        .frame(width: videoSize.width, height: videoSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Video Player View

struct EditorVideoPlayerView: View {
    let player: AVPlayer
    let availableSize: CGSize
    let displayMode: VideoDisplayMode
    let selectedClip: VideoClip?
    let projectState: ProjectState
    let captionData: (Caption, CMTime)?
    let project: VideoProject?

    var body: some View {
        let videoSize = VideoSizeCalculator.calculateVideoSize(availableSize: availableSize)
        let usableWidth = availableSize.width - 16
        let usableHeight = availableSize.height - 16

        Group {
            switch displayMode {
            case .fit:
                videoContent
                    .frame(width: videoSize.width, height: videoSize.height)

            case .fill:
                videoContent
                    .frame(width: usableWidth, height: usableHeight)
                    .clipped()

            case .actual:
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    videoContent
                        .frame(minWidth: 640, minHeight: 360)
                }
                .frame(width: usableWidth, height: usableHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        AdvancedVideoPlayer(player: player)
            .overlay {
                CanvasOverlay(clip: selectedClip, projectState: projectState)
                if let project = project, let captionData = captionData {
                    CaptionOverlayView(
                        caption: captionData.0,
                        currentTime: captionData.1,
                        style: project.captionStyle,
                        offset: .constant(project.captionOffset)
                    )
                }
            }
    }
}
