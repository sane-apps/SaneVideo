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
                        .fill(Color.stone.opacity(0.3))
                        .frame(width: 60, height: 34)
                        .cornerRadius(4)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(Color.stone)
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
                        .foregroundColor(Color.stone)

                    // Caption badge - simple indicator without count
                    if !clip.captions.isEmpty {
                        Image(systemName: "captions.bubble.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .help("Captions ready")
                    }
                }
            }

            Spacer()
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .clear, radius: 4, x: 0, y: 2)
        .animation(.smoothUI, value: isSelected)
        .smoothAppear()
        .accessibilityIdentifier("sidebar.clip_row.\(clip.id)")
        .task {
            thumbnail = await ServiceContainer.shared.thumbnailService.thumbnail(
                for: clip,
                time: .zero,
                size: CGSize(width: 120, height: 68)
            )?.value
        }
    }

    private func formatDuration(_ time: CMTime) -> String {
        TimeUtils.formatDuration(time)
    }
}
