//
//  LibraryClipRow.swift
//  SaneVideo
//
//  Library clip row for displaying clips in the sidebar
//

import CoreMedia
import SwiftUI

/// Library clip row for Advanced mode
struct LibraryClipRow: View {
    let clip: VideoClip
    let isSelected: Bool
    @State private var thumbnail: NSImage?

    /// Display-friendly name for the clip
    private var displayName: String {
        let filename = clip.url.deletingPathExtension().lastPathComponent
        // Check if filename is a UUID (recordings use UUID names)
        if UUID(uuidString: filename) != nil {
            // It's a recording with UUID name - show shortened version
            let prefix = String(filename.prefix(8))
            return String(localized: "sidebar.clip.recording", defaultValue: "Recording") + " \(prefix)"
        }
        return filename
    }

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 34)
                        .clipped()
                        .cornerRadius(Theme.Dimensions.smallCornerRadius)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 60, height: 34)
                        .cornerRadius(4)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(.secondary)
                        )
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(formatDuration(clip.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Caption badge
                    if !clip.captions.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "captions.bubble.fill")
                                .font(.system(size: 8))
                            Text("\(clip.captions.count)")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(4)
                    }
                }
            }

            Spacer()
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .accessibilityIdentifier("sidebar.clip_row.\(clip.id)")
        .task {
            thumbnail = await ServiceContainer.shared.timelineThumbnailService.thumbnail(
                for: clip,
                time: .zero,
                size: CGSize(width: 120, height: 68)
            )
        }
    }

    private func formatDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
