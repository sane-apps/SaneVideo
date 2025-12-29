//
//  TranscriptionEnginePicker.swift
//  SaneVideo
//
//  UI for selecting transcription engine with smart suggestions
//

import SwiftUI

struct TranscriptionEnginePicker: View {
    @Bindable var prefs = ServiceContainer.shared.userPreferences
    @State private var coordinator = ServiceContainer.shared.transcriptionCoordinator
    @State private var showingWhisperKitSuggestion = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Engine Selection
            Picker("Transcription Engine", selection: Binding(
                get: { prefs.transcriptionEngine },
                set: { newValue in
                    prefs.transcriptionEngine = newValue
                    coordinator.setEngine(newValue)
                }
            )) {
                ForEach(TranscriptionEngine.allCases) { engine in
                    HStack {
                        Image(systemName: engine.icon)
                        Text(engine.displayName)
                    }
                    .tag(engine)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("settings.transcription_engine_picker")
            
            // Description
            Text(prefs.transcriptionEngine.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Smart Suggestion Banner
            if coordinator.shouldSuggestWhisperKit && prefs.transcriptionEngine == .apple {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try WhisperKit for better accuracy")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Apple Speech failed multiple times. WhisperKit may work better for your audio.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Switch") {
                        prefs.transcriptionEngine = .whisperKit
                        coordinator.setEngine(.whisperKit)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .scale))
            }
        }
        .onAppear {
            // Check if we should show suggestion
            showingWhisperKitSuggestion = coordinator.shouldSuggestWhisperKit
        }
        .onChange(of: coordinator.shouldSuggestWhisperKit) { _, newValue in
            showingWhisperKitSuggestion = newValue
        }
    }
}
