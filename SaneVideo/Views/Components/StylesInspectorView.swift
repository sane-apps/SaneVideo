import SwiftUI

struct StylesInspectorView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?

    // Clean Up opens by default because it is the main job; the rest start closed.
    @State private var showMagicFix = true
    @State private var showReframe = false
    @State private var showBackground = false
    @State private var showEffects = false
    @State private var showAudioAnalysis = false
    @State private var showClipInfo = false

    // Track if operation is in progress to prevent mode switching
    @State private var isOperationInProgress = false

    private var validatedClip: VideoClip? {
        guard let project = appState.projectState.currentProject else {
            return nil
        }

        let allClips = project.timeline.tracks.flatMap(\.clips)

        if let clip = selectedClip,
           let currentClip = allClips.first(where: { $0.id == clip.id }) {
            return currentClip
        }

        if let selectedId = appState.selectedClipIds.first,
           let selectedClip = allClips.first(where: { $0.id == selectedId }) {
            return selectedClip
        }

        if allClips.count == 1 {
            return allClips[0]
        }

        return nil
    }

    var body: some View {
        @Bindable var projectState = appState.projectState

        VStack(spacing: 0) {
            HStack {
                InspectorHeader()
                Spacer()
            }
            .padding(.trailing, 16)

            if let clip = validatedClip {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        CollapsibleSection(
                            title: "Clean Up",
                            icon: "wand.and.stars",
                            isExpanded: $showMagicFix,
                            isPrimary: true
                        ) {
                            SmartToolsSection(clip: clip, options: $projectState.magicFixOptions, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: "Framing",
                            icon: "crop",
                            isExpanded: $showReframe
                        ) {
                            VideoSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: "Background",
                            icon: "person.crop.rectangle",
                            isExpanded: $showBackground,
                            badge: clip.backgroundEffect != nil ? "On" : nil
                        ) {
                            BackgroundEffectsView(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: "Effects",
                            icon: "sparkles",
                            isExpanded: $showEffects,
                            badge: clip.effects.isEmpty ? nil : "Active"
                        ) {
                            EffectsPickerView(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: "Audio",
                            icon: "waveform.badge.magnifyingglass",
                            isExpanded: $showAudioAnalysis
                        ) {
                            AudioSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: "Clip Info",
                            icon: "info.circle",
                            isExpanded: $showClipInfo
                        ) {
                            ClipInfoSection(clip: clip)
                        }
                    }
                    .padding(.bottom, 20)
                }
            } else {
                EmptySelectionView()
            }
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .background(Theme.Colors.editorPanel)
        .onChange(of: appState.projectState.currentProject?.id) { _, _ in
            if selectedClip != nil, validatedClip == nil {
                selectedClip = nil
                AppLogger.general.info("Inspector: Auto-deselected deleted clip")
            }
        }
        .onChange(of: selectedClip?.id) { _, _ in
            if selectedClip != nil, validatedClip == nil {
                selectedClip = nil
            }
        }
        .onChange(of: appState.projectState.isProcessing) { _, isProcessing in
            isOperationInProgress = isProcessing
        }
    }
}
