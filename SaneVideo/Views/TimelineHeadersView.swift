// Fixed left column headers for timeline tracks

import SwiftUI

struct TimelineHeadersView: View {
    let zoomLevel: CGFloat
    let pixelsPerSecond: CGFloat

    @Environment(AppState.self) var appState

    private let timelineHeight: CGFloat = AppConstants.timelineHeight

    // Compute filtered tracks ONCE to ensure headers and rows stay in sync
    private var tracksWithClips: [Track] {
        appState.projectState.currentProject?.timeline.tracks.filter { !$0.clips.isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Must match the TimeRulerView height (40pt) exactly.
            Color.clear
                .frame(height: 40)
                .frame(width: 100)

            // Spacing must match the track rows VStack (8pt).
            VStack(alignment: .leading, spacing: 8) {
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
                    .frame(height: timelineHeight, alignment: .top) // Must match the track row height.
                }
            }
            .frame(width: 100, alignment: .topLeading)
        }
        .frame(width: 100, alignment: .topLeading)
        .allowsHitTesting(true) // Headers must stay clickable.
    }
}
