import SwiftUI

struct TranscriptionEnginePicker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("On-device transcription", systemImage: "waveform")
                .saneReadableBodyStrong()
                .accessibilityIdentifier("settings.transcription_engine_picker")
            Text("Captions and transcripts are created on your Mac. A speech model downloads before first use.")
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
