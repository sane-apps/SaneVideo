//
//  FileDropModifier.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import UniformTypeIdentifiers

struct FileDropModifier: ViewModifier {
    @Environment(AppState.self) var appState

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                let validProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
                guard let provider = validProviders.first else { return false }

                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else {
                        // Fallback for some Finder drops where item is the URL directly
                        if let url = item as? URL {
                            Task { @MainActor in
                                self.handleDrop(url: url)
                            }
                        }
                        return
                    }
                    Task { @MainActor in
                        self.handleDrop(url: url)
                    }
                }
                return true
            }
    }

    private func handleDrop(url: URL) {
        Task { @MainActor in
            AppLogger.uiLog.info("File dropped: \(url.lastPathComponent)")

            // Check if valid video file
            if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
                AppLogger.uiLog.info("Valid video file, importing...")
                await appState.projectState.addVideoToTimeline(url: url)
            } else {
                AppLogger.uiLog.warning("Dropped file is not a video: \(url.pathExtension)")
                ServiceContainer.shared.toastManager.show("Not a video file", type: .error)
            }
        }
    }
}

extension View {
    func withFileDropHandling() -> some View {
        modifier(FileDropModifier())
    }
}
