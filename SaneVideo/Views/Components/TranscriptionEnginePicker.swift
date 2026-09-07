import SwiftUI

struct TranscriptionEnginePicker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("WhisperKit", systemImage: "waveform")
                .saneReadableBodyStrong()
                .accessibilityIdentifier("settings.transcription_engine_picker")
            Text("Captions and transcripts use the large-v3-turbo model on your Mac. The model downloads before first use.")
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
