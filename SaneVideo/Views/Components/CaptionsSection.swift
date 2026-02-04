//
//  CaptionsSection.swift
//  SaneVideo
//
//  2025-12-31: Simplified to quick access. Full caption editing in Transcript sidebar tab.
//

import AVFoundation
import SwiftUI

// MARK: - Captions Section (Simplified)

struct CaptionsSection: View {
    @Environment(AppState.self) var appState
    let clip: VideoClip
    @Binding var isOperationInProgress: Bool

    @State private var isGeneratingCaptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Captions", systemImage: "text.bubble")
                    .font(.headline)
                Spacer()

                // Quick style indicator
                if let project = appState.projectState.currentProject {
                    Text(project.captionStyle.name)
                        .font(.caption)
                        .foregroundColor(Color.stone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.stone.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            // Status & Quick Action
            if clip.captions.isEmpty {
                emptyCaptionsView
            } else {
                captionsReadyView
            }
        }
    }

    // MARK: - Empty State

    private var emptyCaptionsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(Color.stone)
                Text("No captions yet")
                    .font(.caption)
                    .foregroundColor(Color.stone)
            }

            Button {
                Task { await generateCaptions() }
            } label: {
                HStack {
                    Image(systemName: "text.bubble.fill")
                    Text("Generate Captions")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isOperationInProgress || clip.isMissing || isGeneratingCaptions)
            .overlay {
                if isGeneratingCaptions {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .accessibilityIdentifier("captions.generate_button")

            Text("Or use Magic Fix for full cleanup")
                .font(.caption2)
                .foregroundColor(Color.stone)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Captions Ready State

    private var captionsReadyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status
            HStack {
                Label("\(clip.captions.count) captions", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
            }

            // Redirect to Transcript tab
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.accentColor)
                Text("Edit in **Transcript** sidebar tab")
                    .font(.caption)
                    .foregroundColor(Color.stone)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.stone.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Generate Action

    private func generateCaptions() async {
        guard !clip.isMissing else {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Cannot generate captions: Clip file is missing",
                    type: .error
                )
            }
            return
        }

        isGeneratingCaptions = true
        defer {
            Task { @MainActor in
                isGeneratingCaptions = false
            }
        }

        do {
            let coordinator = ServiceContainer.shared.transcriptionCoordinator
            let captions = try await coordinator.generateCaptions(
                for: clip.url,
                progressHandler: { _, _, _ in }
            )

            await MainActor.run {
                appState.projectState.updateCaptions(for: clip, newCaptions: captions)
                ServiceContainer.shared.toastManager.show("Captions generated!", type: .success)
            }
        } catch {
            await MainActor.run {
                ServiceContainer.shared.toastManager.show(
                    "Caption generation failed: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
}
