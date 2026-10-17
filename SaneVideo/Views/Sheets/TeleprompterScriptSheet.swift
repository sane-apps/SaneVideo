import SwiftUI

/// Edits the project's teleprompter script and how it scrolls.
struct TeleprompterScriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var notes = SpeakerNotes()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teleprompter Script")
                .font(.title2.weight(.semibold))

            TextEditor(text: $notes.text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.quaternary, in: .rect(cornerRadius: 10))
                .frame(minHeight: 220)
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Type or paste what you want to read while recording.")
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Text size")
                    Slider(value: $notes.fontSize, in: 18 ... 60)
                }
                GridRow {
                    Text("Scroll speed")
                    Slider(value: $notes.scrollSpeed, in: 5 ... 80)
                }
                GridRow {
                    Text("Mirror")
                    Toggle("Flip text for a mirrored teleprompter", isOn: $notes.isMirrored)
                }
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") { save(show: false) }
                Button("Save and Show") { save(show: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!notes.hasContent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { notes = appState.currentProject?.speakerNotes ?? SpeakerNotes() }
    }

    private func save(show: Bool) {
        appState.setTeleprompterVisible(show, notesOverride: notes)
        dismiss()
    }
}
