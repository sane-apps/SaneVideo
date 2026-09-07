import AVFoundation
import SaneUI
import SwiftUI

struct RecordingSettingsView: View {
    @Bindable var prefs = ServiceContainer.shared.userPreferences

    var body: some View {
        SaneSettingsPage {
            Text("Defaults for new camera recordings. Existing clips keep their original settings.")
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)

            CompactSection("Camera", icon: "video", iconColor: .red) {
                CompactRow("Resolution") {
                    Picker("Resolution", selection: $prefs.recordingResolution) {
                        Text("720p HD").tag(SaneExportSettings.ExportResolution.hd720)
                        Text("1080p HD").tag(SaneExportSettings.ExportResolution.hd1080)
                        Text("4K UHD").tag(SaneExportSettings.ExportResolution.uhd4K)
                    }
                    .labelsHidden()
                    .help("Choose the resolution for new camera recordings.")
                    .accessibilityIdentifier("settings.recording.resolution_picker")
                }
                CompactDivider()
                CompactRow("Frame rate") {
                    Picker("Frame Rate", selection: $prefs.recordingFPS) {
                        Text("30 fps").tag(30.0)
                        Text("60 fps").tag(60.0)
                    }
                    .labelsHidden()
                    .help("30 fps suits most videos. Use 60 fps for fast movement.")
                    .accessibilityIdentifier("settings.recording.fps_picker")
                }
                CompactDivider()
                CompactToggle(label: "Mirror camera preview", isOn: $prefs.mirrorCameraPreview)
                    .help("Show a mirrored preview while recording.")
                    .accessibilityIdentifier("settings.recording.mirror_camera_preview")
            }

            CompactSection("Screen Recording", icon: "display", iconColor: .cyan) {
                CompactToggle(label: "Hide SaneVideo", isOn: $prefs.excludeAppFromRecording)
                    .help("Exclude SaneVideo windows from screen recordings.")
                    .accessibilityIdentifier("settings.recording.exclude_app")
                HelperText(
                    text: "Screen resolution follows the screen or window you select.",
                    icon: "viewfinder"
                )
                .padding(12)
            }
        }
    }
}
