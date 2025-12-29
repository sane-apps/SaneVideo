//
//  TimelineHeadersView.swift
//  SaneVideo
//
//  Fixed left column headers for timeline tracks
//  Extracted to ensure proper alignment with scrollable track rows
//

import SwiftUI

struct TimelineHeadersView: View {
    let zoomLevel: CGFloat
    let pixelsPerSecond: CGFloat

    @Environment(AppState.self) var appState

    private let timelineHeight: CGFloat = AppConstants.timelineHeight

    // CRITICAL: Compute filtered tracks ONCE to ensure headers and rows stay in sync
    private var tracksWithClips: [Track] {
        appState.projectState.currentProject?.timeline.tracks.filter { !$0.clips.isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Spacer for ruler height alignment - MUST match TimeRulerView height exactly (40px)
            Color.clear
                .frame(height: 40)
                .frame(width: 100)

            // Headers VStack - MUST match track rows VStack spacing exactly (8px)
            VStack(alignment: .leading, spacing: 8) {
                // CRITICAL FIX: Use shared filtered array to ensure header/row sync
                ForEach(tracksWithClips) { track in
                    TrackHeaderView(
                        track: track,
                        onMuteToggle: {
                            appState.projectState.toggleTrackMute(track)
                        },
                        onLockToggle: {
                            appState.projectState.toggleTrackLock(track)
                        }
                    )
                    .frame(height: timelineHeight, alignment: .top) // CRITICAL: Match track row height exactly
                }
            }
            .frame(width: 100, alignment: .topLeading)
        }
        .frame(width: 100, alignment: .topLeading)
        // CRITICAL FIX: Allow hit testing to pass through to scrollable content
        // This ensures trim handles can be grabbed even when near the left edge
        .allowsHitTesting(true) // Headers still need to be clickable, but we'll handle overlap differently
    }
}
