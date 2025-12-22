//
//  TrackHeaderView.swift
//  SaneVideo
//
//  Extracted from TimelineView.swift
//  Contains track header and add track button
//

import AppKit
import SwiftUI

// MARK: - Track Header View

struct TrackHeaderView: View {
    let track: Track
    let onMuteToggle: () -> Void
    let onLockToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Track Name & Type Icon
            HStack(spacing: 4) {
                Image(systemName: trackIcon)
                    .font(.caption)
                    .foregroundColor(track.isMuted ? .secondary : trackColor)

                if !track.name.isEmpty && track.name != "Video 1" {
                    Text(track.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .foregroundColor(track.isMuted ? .secondary : .primary)
                }
            }

            // Controls
            HStack(spacing: 8) {
                // Mute Button
                Button(action: onMuteToggle) {
                    Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(track.isMuted ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help(track.isMuted ? String(localized: "track.help.unmute", defaultValue: "Unmute Track") : String(localized: "track.help.mute", defaultValue: "Mute Track"))
                .accessibilityIdentifier("track_header.mute_button")

                // Lock Button
                Button(action: onLockToggle) {
                    Image(systemName: track.isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                        .foregroundColor(track.isLocked ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(track.isLocked ? String(localized: "track.help.unlock", defaultValue: "Unlock Track") : String(localized: "track.help.lock", defaultValue: "Lock Track"))
                .accessibilityIdentifier("track_header.lock_button")
            }
        }
        .padding(8)
        .frame(minWidth: 80, idealWidth: 100, maxWidth: 120)
        .frame(height: AppConstants.timelineHeight)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var trackIcon: String {
        switch track.type {
        case .video: return "film"
        case .audio: return "waveform"
        case .overlay: return "text.bubble"
        }
    }

    private var trackColor: Color {
        switch track.type {
        case .video: return .blue
        case .audio: return .green
        case .overlay: return .purple
        }
    }
}

// MARK: - Add Track Button

struct AddTrackButton: View {
    let onAdd: (TrackType) -> Void

    var body: some View {
        Menu {
            Button(action: { onAdd(.video) }, label: {
                Label(String(localized: "track.type.video", defaultValue: "Video Track"), systemImage: "film")
            })
            Button(action: { onAdd(.audio) }, label: {
                Label(String(localized: "track.type.audio", defaultValue: "Audio Track"), systemImage: "waveform")
            })
            Button(action: { onAdd(.overlay) }, label: {
                Label(String(localized: "track.type.overlay", defaultValue: "Overlay Track"), systemImage: "text.bubble")
            })
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                Text(String(localized: "timeline.add_track", defaultValue: "Add Track"))
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.top, 8)
        .padding(.leading, 8)
        .accessibilityIdentifier("timeline.add_track_button")
    }
}
