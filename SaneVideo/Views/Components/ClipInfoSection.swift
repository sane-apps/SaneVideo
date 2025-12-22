//
//  ClipInfoSection.swift
//  SaneVideo
//
//  Displays basic clip metadata (name, duration, resolution)
//

import AVFoundation
import SwiftUI

/// Displays basic metadata about a video clip
struct ClipInfoSection: View {
    let clip: VideoClip
    @State private var resolution: String = "Loading..."

    /// Display-friendly name for the clip
    private var displayName: String {
        let filename = clip.url.deletingPathExtension().lastPathComponent
        if UUID(uuidString: filename) != nil {
            let prefix = String(filename.prefix(8))
            return "Recording \(prefix)"
        }
        return filename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoRow(label: "Name", value: displayName)
            InfoRow(label: "Duration", value: String(format: "%.2fs", clip.duration.seconds))
            InfoRow(label: "Resolution", value: resolution)
        }
        .task(id: clip.url) {
            await loadResolution()
        }
    }

    private func loadResolution() async {
        let asset = AVURLAsset(url: clip.url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                resolution = "\(Int(size.width)) × \(Int(size.height))"
                return
            }
        }
        resolution = "Unknown"
    }
}
