//
//  CursorEnhancementsView.swift
//  SaneVideo
//
//  Controls for cursor visibility enhancements in screen recordings
//

import SwiftUI

/// Controls for enhancing cursor visibility in screen recordings
struct CursorEnhancementsView: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip

    @State private var showHighlight: Bool

    init(clip: VideoClip) {
        self.clip = clip
        _showHighlight = State(initialValue: clip.showCursorHighlight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "cursor.desc", defaultValue: "Enhance cursor visibility for screen recordings"))
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(String(localized: "cursor.toggle", defaultValue: "Show Highlight"), isOn: $showHighlight)
                .accessibilityIdentifier("cursor.toggle")
                .onChange(of: showHighlight) { _, newValue in
                    appState.projectState.updateClipCursorHighlight(clip, show: newValue)
                }
        }
    }
}
