import SwiftUI

struct TranscriptionEnginePicker: View {
    @Bindable var preferences = ServiceContainer.shared.userPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Speech engine", selection: $preferences.transcriptionEngine) {
                ForEach(TranscriptionEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.transcription_engine_picker")
            Text(preferences.transcriptionEngine.description)
                .saneReadableSupportText()
                .fixedSize(horizontal: false, vertical: true)
            Text("Either way, your audio never leaves this Mac.")
                .saneReadableSupportText()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
