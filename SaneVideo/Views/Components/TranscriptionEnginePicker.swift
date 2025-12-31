//
//  TranscriptionEnginePicker.swift
//  SaneVideo
//
//  UI for displaying transcription engine info (WhisperKit-only for macOS 15+)
//

import SwiftUI

struct TranscriptionEnginePicker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Engine Info
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.accentColor)
                Text("WhisperKit")
                    .fontWeight(.medium)
            }
            .accessibilityIdentifier("settings.transcription_engine_picker")

            // Description
            Text(TranscriptionEngine.whisperKit.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Model info badge
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("distil-large-v3 model • 100% on-device • 99 languages")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
