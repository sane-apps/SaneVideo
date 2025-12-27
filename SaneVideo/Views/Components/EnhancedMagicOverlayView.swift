//
//  EnhancedMagicOverlayView.swift
//  SaneVideo
//
//  Enhanced Magic Fix progress overlay with cancellation and better feedback
//

import SwiftUI

/// Enhanced Magic Fix progress overlay with cancellation support
struct EnhancedMagicOverlayView: View {
    @Environment(AppState.self) var appState
    @State private var showCancelConfirmation = false
    
    var body: some View {
        if appState.projectState.isProcessing {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundColor(.purple)
                        .symbolEffect(.pulse, options: .repeating)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Magic Fix")
                            .font(.headline)
                        if let status = appState.projectState.processingStatus {
                            Text(status)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Cancel button
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel Magic Fix")
                }
                
                // Progress bar
                if appState.projectState.processingProgress > 0 {
                    ProgressView(value: appState.projectState.processingProgress)
                        .progressViewStyle(.linear)
                    
                    Text("\(Int(appState.projectState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                
                // Estimated time remaining (if we can calculate it)
                if appState.projectState.processingProgress > 0.1 {
                    Text("This may take a few minutes...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .frame(width: 400)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 20)
            .transition(.scale.combined(with: .opacity))
            .accessibilityIdentifier(AccessibilityIdentifiers.magicProgressOverlay)
            .alert("Cancel Magic Fix?", isPresented: $showCancelConfirmation) {
                Button("Continue Processing", role: .cancel) {}
                Button("Cancel", role: .destructive) {
                    cancelMagicFix()
                }
            } message: {
                Text("Canceling will stop the current Magic Fix operation. Any progress will be lost.")
            }
        }
    }
    
    private func cancelMagicFix() {
        // Cancel the processing task
        // Note: This requires adding cancellation support to ProjectState
        Task {
            await appState.projectState.cancelProcessing()
        }
    }
}
