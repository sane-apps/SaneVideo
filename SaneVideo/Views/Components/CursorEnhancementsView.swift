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
                .accessibilityLabel("Show cursor highlight")
                .accessibilityHint("Enhances cursor visibility in screen recordings by adding a highlight effect")
                .focusable() // P0 FIX: Keyboard navigation
                .onChange(of: showHighlight) { _, newValue in
                    appState.projectState.updateClipCursorHighlight(clip, show: newValue)
                }
            // CRITICAL FIX: Sync state when clip changes externally
            .onChange(of: clip.showCursorHighlight) { _, newValue in
                if showHighlight != newValue {
                    showHighlight = newValue
                }
            }
        }
    }
}
