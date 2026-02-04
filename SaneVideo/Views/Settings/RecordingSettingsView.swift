//
//  RecordingSettingsView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct RecordingSettingsView: View {
  @Bindable var prefs = ServiceContainer.shared.userPreferences

  var body: some View {
    Form {
      Section(header: Text("Recording Configuration").font(.headline)) {
        Text(
          "These settings apply to camera recordings. Screen recording resolution is determined by the screen source."
        )
        .font(.caption)
        .foregroundColor(Color.stone)
        .padding(.bottom, 8)

        Picker("Resolution", selection: $prefs.recordingResolution) {
          Text("1080p HD").tag(SaneExportSettings.ExportResolution.hd1080)
          Text("4K UHD").tag(SaneExportSettings.ExportResolution.uhd4K)
          Text("720p HD").tag(SaneExportSettings.ExportResolution.hd720)
        }
        .accessibilityIdentifier("settings.recording.resolution_picker")

        Picker("Frame Rate", selection: $prefs.recordingFPS) {
          Text("30 fps").tag(30.0)
          Text("60 fps").tag(60.0)
        }
        .accessibilityIdentifier("settings.recording.fps_picker")
      }

      Section(header: Text("Screen Recording").font(.headline)) {
        Toggle("Exclude SaneVideo from Recording", isOn: $prefs.excludeAppFromRecording)
          .accessibilityIdentifier("settings.recording.exclude_app")
        Text("When enabled, the SaneVideo window will not appear in screen recordings.")
          .font(.caption)
          .foregroundColor(Color.stone)
      }
    }
    .padding()
  }
}
