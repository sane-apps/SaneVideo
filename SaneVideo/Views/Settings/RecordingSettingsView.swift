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
      Section {
        InformationBox(
          text: "These defaults affect new recordings on this Mac. They do not change existing clips already in your projects.",
          color: Theme.Colors.accent,
          icon: "record.circle.fill"
        )
      }

      Section(header: Text("Recording Configuration").saneReadableSectionTitle()) {
        Text(
          "These settings apply to camera recordings. Screen recording resolution is determined by the screen source."
        )
        .saneReadableSupportText()
        .padding(.bottom, 8)

        Picker("Resolution", selection: $prefs.recordingResolution) {
          Text("1080p HD").tag(SaneExportSettings.ExportResolution.hd1080)
          Text("4K UHD").tag(SaneExportSettings.ExportResolution.uhd4K)
          Text("720p HD").tag(SaneExportSettings.ExportResolution.hd720)
        }
        .help("Choose the default quality for camera recordings on this Mac.")
        .accessibilityIdentifier("settings.recording.resolution_picker")

        HelperText(
          text: "Use 1080p for normal demos. Use 4K if you want extra room for reframing and cropping later.",
          icon: "viewfinder.circle.fill"
        )

        Picker("Frame Rate", selection: $prefs.recordingFPS) {
          Text("30 fps").tag(30.0)
          Text("60 fps").tag(60.0)
        }
        .help("Choose the default smoothness for camera recordings.")
        .accessibilityIdentifier("settings.recording.fps_picker")

        HelperText(
          text: "30 fps is the normal demo default. Use 60 fps for motion-heavy recordings or very fluid cursor movement.",
          icon: "speedometer"
        )
      }

      Section(header: Text("Screen Recording").saneReadableSectionTitle()) {
        Toggle("Exclude SaneVideo from Recording", isOn: $prefs.excludeAppFromRecording)
          .help("Hide the SaneVideo window from screen captures when you record your screen.")
          .accessibilityIdentifier("settings.recording.exclude_app")
        Text("When enabled, the SaneVideo window will not appear in screen recordings.")
          .saneReadableSupportText()
      }
    }
    .padding()
  }
}
