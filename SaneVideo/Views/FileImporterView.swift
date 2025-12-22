//
//  FileImporterView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import UniformTypeIdentifiers

struct FileImporterView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState

    @State private var isTargeted = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 24) {
            Text(String(localized: "import.title", defaultValue: "Import Video"))
                .font(.headline)

            // Drop Zone
            Button {
                isImporting = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundStyle(isTargeted ? Theme.Colors.action : Theme.Colors.textSecondary.opacity(0.5))
                        .background(isTargeted ? Theme.Colors.action.opacity(0.1) : Color.clear)
                        .background(Material.regular)
                        .cornerRadius(Theme.Dimensions.cornerRadius)
                        .shadow(radius: 10)
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 32))
                        Text(String(localized: "import.drop_zone.title", defaultValue: "Drag & Drop Video Here"))
                            .font(.body)
                        Text(String(localized: "import.drop_zone.subtitle", defaultValue: "or click to browse"))
                    }
                    .foregroundStyle(isTargeted ? Theme.Colors.action : Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .frame(height: 140)
            .accessibilityIdentifier("import.drop_zone")
            .onDrop(of: [.movie, .video, .fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .mpeg, .mpeg2Video, .avi, .audiovisualContent],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case let .success(urls):
                    guard !urls.isEmpty else { return }
                    // Dismiss immediately for responsive UI (optimistic loading)
                    dismiss()

                    // Process ALL selected files, not just the first
                    for url in urls {
                        // Security scope for fileImporter URLs
                        let accessGranted = url.startAccessingSecurityScopedResource()

                        // Load in background to avoid blocking main thread
                        Task.detached(priority: .userInitiated) {
                            // Note: We keep security scope open for AVAsset access
                            if !accessGranted {
                                await MainActor.run {
                                    AppLogger.project.warning("Security scope not granted for \(url.lastPathComponent)")
                                }
                            }
                            await ServiceContainer.shared.appState.addVideoToTimeline(url: url)
                        }
                    }
                case let .failure(error):
                    AppLogger.project.error("Import failed: \(error)")
                }
            }

            Button(String(localized: "action.cancel", defaultValue: "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.large)
            .accessibilityIdentifier("import.action.cancel")
        }
        .padding(30)
        .frame(width: 440)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try to load as a URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            // Dismiss immediately for responsive UI
            dismiss()

            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    // Load in background
                    Task.detached(priority: .userInitiated) {
                        await ServiceContainer.shared.appState.addVideoToTimeline(url: url)
                    }
                }
            }
            return true
        }
        return false
    } // End handleDrop
}
