import SwiftUI

/// Enhanced Magic Fix progress overlay with cancellation support
struct EnhancedMagicOverlayView: View {
    @Environment(AppState.self) var appState
    @State private var showCancelConfirmation = false

    private var processingStatus: String {
        appState.projectState.processingStatus ?? ""
    }

    private var overlayTitle: String {
        let lowercased = processingStatus.lowercased()
        if lowercased.contains("transcrib") || lowercased.contains("caption") {
            return "Captions"
        }
        return "Magic Fix"
    }

    private var overlayIcon: String {
        overlayTitle == "Captions" ? "captions.bubble.fill" : "wand.and.stars"
    }

    private var cancelActionTitle: String {
        overlayTitle == "Captions" ? "Cancel caption generation?" : "Cancel Magic Fix?"
    }

    private var cancelActionMessage: String {
        overlayTitle == "Captions"
            ? "Canceling will stop the current caption generation run. Any progress will be lost."
            : "Canceling will stop the current Magic Fix operation. Any progress will be lost."
    }
    
    var body: some View {
        if appState.projectState.isProcessing {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: overlayIcon)
                        .font(.title2)
                        .foregroundColor(Theme.Colors.accent)
                        .symbolEffect(.pulse, options: .repeating)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(overlayTitle)
                            .font(.headline)
                        if !processingStatus.isEmpty {
                            Text(processingStatus)
                                .font(.subheadline)
                                .foregroundColor(Color.stone)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        showCancelConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color.stone)
                    }
                    .buttonStyle(.plain)
                    .help(overlayTitle == "Captions" ? "Cancel caption generation" : "Cancel Magic Fix")
                }
                
                if appState.projectState.processingProgress > 0 {
                    ProgressView(value: appState.projectState.processingProgress)
                        .progressViewStyle(.linear)
                    
                    Text("\(Int(appState.projectState.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(Color.stone)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                
                if appState.projectState.processingProgress > 0.1 {
                    Text("This may take a few minutes...")
                        .font(.caption2)
                        .foregroundColor(Color.stone)
                }
            }
            .padding(20)
            .frame(width: 400)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 20)
            .transition(.scale.combined(with: .opacity))
            .accessibilityIdentifier(AccessibilityIdentifiers.magicProgressOverlay)
            .alert(cancelActionTitle, isPresented: $showCancelConfirmation) {
                Button("Continue Processing", role: .cancel) {}
                Button("Cancel", role: .destructive) {
                    cancelMagicFix()
                }
            } message: {
                Text(cancelActionMessage)
            }
        }
    }
    
    private func cancelMagicFix() {
        Task {
            await appState.projectState.cancelProcessing()
        }
    }
}
