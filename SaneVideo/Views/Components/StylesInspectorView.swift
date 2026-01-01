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
        guard let clip = selectedClip,
              let project = appState.projectState.currentProject else {
            return nil
        }
        // CRITICAL FIX: Safely access timeline.tracks to prevent crash
        guard !project.timeline.tracks.isEmpty else {
            return nil
        }
        // Verify clip still exists in project
        for track in project.timeline.tracks where track.clips.contains(where: { $0.id == clip.id }) {
            // CRITICAL FIX: Get fresh clip from project to ensure we have latest state
            return track.clips.first(where: { $0.id == clip.id })
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
                    // CRITICAL FIX: Use LazyVStack for better performance with many sections
                    // P0 FIX: Add keyboard navigation support
                    LazyVStack(spacing: 0) {
                        // ═══════════════════════════════════════════
                        // MAGIC FIX (Core Feature)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Magic Fix",
                            icon: "wand.and.stars",
                            isExpanded: $showMagicFix
                        ) {
                            SmartToolsSection(clip: clip, options: $projectState.magicFixOptions, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // REFRAME (Auto-Zoom, Smart Crop)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Reframe",
                            icon: "crop",
                            isExpanded: $showReframe
                        ) {
                            VideoSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // BACKGROUND (AI Replacement)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: clip.backgroundEffect != nil ? "Background ✓" : "Background",
                            icon: "person.crop.rectangle",
                            isExpanded: $showBackground,
                            badge: clip.backgroundEffect != nil ? "On" : nil
                        ) {
                            BackgroundEffectsView(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // EFFECTS (Filters, LUTs)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Effects",
                            icon: "sparkles",
                            isExpanded: $showEffects,
                            badge: clip.effects.isEmpty ? nil : "Active"
                        ) {
                            EffectsPickerView(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // AUDIO ANALYSIS (Find Highlights, Analyze)
                        // ═══════════════════════════════════════════
                        CollapsibleSection(
                            title: "Audio Analysis",
                            icon: "waveform.badge.magnifyingglass",
                            isExpanded: $showAudioAnalysis
                        ) {
                            AudioSection(clip: clip, isOperationInProgress: $isOperationInProgress)
                        }

                        Divider().padding(.horizontal)

                        // ═══════════════════════════════════════════
                        // CLIP INFO (Metadata, Locate File)
                        // ═══════════════════════════════════════════
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
        // P1 FIX: Increase Inspector width for better spacing
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        // CONSISTENCY: Use controlBackgroundColor to match main editor
        .background(Color(nsColor: .controlBackgroundColor))
        // CRITICAL FIX: Auto-deselect if clip is deleted
        .onChange(of: appState.projectState.currentProject?.id) { _, _ in
            // CRITICAL FIX: Safely check if clip still exists
            if selectedClip != nil, validatedClip == nil {
                // Clip was deleted or project changed, deselect it
                selectedClip = nil
                AppLogger.general.info("Inspector: Auto-deselected deleted clip")
            }
        }
        // CRITICAL FIX: Sync selectedClip if it becomes invalid
        .onChange(of: selectedClip?.id) { _, _ in
            if selectedClip != nil, validatedClip == nil {
                // Selected clip doesn't exist, deselect
                selectedClip = nil
            }
        }
        // CRITICAL FIX: Monitor for operations in progress
        .onChange(of: appState.projectState.isProcessing) { _, isProcessing in
            isOperationInProgress = isProcessing
        }
    }
}
