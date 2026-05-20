//
//  StylesInspectorView.swift
//  SaneVideo
//
//  2025-12-31: Simplified inspector layout
//  - Captions moved to Transcript tab (left sidebar)
//  - Sections: Magic Fix, Reframe, Background, Effects, Audio Analysis, Clip Info
//  - Fresh start each launch (all collapsed, no persistence)
//

import SwiftUI

struct StylesInspectorView: View {
    @Environment(AppState.self) var appState
    @Binding var selectedClip: VideoClip?

    // UX: All sections collapsed by default, fresh start each launch (no @AppStorage)
    @State private var showMagicFix = false
    @State private var showReframe = false
    @State private var showBackground = false
    @State private var showEffects = false
    @State private var showAudioAnalysis = false
    @State private var showClipInfo = false

    // CRITICAL FIX: Track if operation is in progress to prevent mode switching
    @State private var isOperationInProgress = false

    // CRITICAL FIX: Validate clip exists in current project
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
            // UX FIX: Clean header without mode toggle - unified experience
            HStack {
                InspectorHeader()
                Spacer()
            }
            .padding(.trailing, 16)

            // CRITICAL FIX: Validate clip exists before rendering
            if let clip = validatedClip {
                ScrollView {
                    LazyVStack(spacing: Theme.Dimensions.spacingMD) {
                        CollapsibleSection(
                            title: "Magic Fix",
                            icon: "wand.and.stars",
                            isExpanded: $showMagicFix
                        ) {
                            SmartToolsSection(clip: clip, options: $projectState.magicFixOptions, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: "Reframe",
                            icon: "crop",
                            isExpanded: $showReframe
                        ) {
                            VideoSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        CollapsibleSection(
                            title: clip.backgroundEffect != nil ? "Background ✓" : "Background",
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
                            title: "Audio Analysis",
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
                    .padding(.horizontal, Theme.Dimensions.paddingSM)
                    .padding(.vertical, Theme.Dimensions.paddingSM)
                    .padding(.bottom, 20)
                }
            } else {
                EmptySelectionView()
            }
        }
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor),
                        Theme.Colors.ambientDeep.opacity(0.70),
                        Theme.Colors.ambientMid.opacity(0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Theme.Colors.accentGlow.opacity(0.22), .clear],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: 240
                )
            }
        }
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
