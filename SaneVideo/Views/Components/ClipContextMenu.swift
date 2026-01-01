//
//  ClipContextMenu.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import AppKit

/// Context menu for TimelineClipView
/// 2025-12-31: Simplified to remove duplicates. Use canonical locations instead:
/// - Smart Crop → VideoSection in inspector
/// - Auto-Framing → VideoSection in inspector
/// - Find Highlights → AudioSection in inspector
struct ClipContextMenu: View {
    let clip: VideoClip

    var onSplit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onRemoveSilence: (() -> Void)?
    var onRemoveFillers: (() -> Void)?
    var onGenerateCaptions: (() -> Void)?
    var onFindGestures: (() -> Void)?
    var onPrivacyBlur: (() -> Void)?
    var onRelink: (() -> Void)?
    var onDeleteFile: (() -> Void)?
    var onSetTransition: ((TransitionType) -> Void)?

    var body: some View {
        Group {
            Button(action: { onSplit?() }, label: {
                Label(String(localized: "clip.menu.split", defaultValue: "Split Clip"), systemImage: "scissors")
            })
            .accessibilityIdentifier("clip.menu.split")

            Button(action: { onDelete?() }, label: {
                Label(String(localized: "clip.menu.delete", defaultValue: "Delete"), systemImage: "trash")
            })
            .accessibilityIdentifier("clip.menu.delete")

            Divider()

            // MARK: - Quick Cleanup (Simplified - 2025-12-31)
            // Full options available in Magic Fix inspector section
            Button(action: { onRemoveSilence?() }, label: {
                Label(String(localized: "clip.menu.remove_silence", defaultValue: "Remove Silence"), systemImage: "waveform.path")
            })
            .accessibilityIdentifier("clip.menu.remove_silence")

            Button(action: { onRemoveFillers?() }, label: {
                Label(String(localized: "clip.menu.remove_fillers", defaultValue: "Remove Filler Words"), systemImage: "text.badge.minus")
            })
            .disabled(clip.captions.isEmpty)
            .accessibilityIdentifier("clip.menu.remove_fillers")

            // MARK: - Vision Analysis (unique features only)
            // Smart Crop & Auto-Framing moved to VideoSection inspector
            Menu {
                Button(action: {
                    onFindGestures?()
                    AppLogger.project.info("Find Gestures requested for clip")
                }, label: {
                    Label(String(localized: "clip.menu.find_gestures", defaultValue: "Find Gestures"), systemImage: "figure.wave")
                })
                .accessibilityIdentifier("clip.menu.find_gestures")

                Button(action: {
                    onPrivacyBlur?()
                    AppLogger.project.info("Privacy Blur requested for clip")
                }, label: {
                    Label(String(localized: "clip.menu.privacy_blur", defaultValue: "Blur Sensitive Text"), systemImage: "eye.slash")
                })
                .accessibilityIdentifier("clip.menu.privacy_blur")
            } label: {
                Label(String(localized: "clip.menu.vision", defaultValue: "Vision Analysis"), systemImage: "eye")
            }

            // MARK: - Captions
            Button(action: { onGenerateCaptions?() }, label: {
                Label(String(localized: "clip.menu.generate_captions", defaultValue: "Generate Captions"), systemImage: "captions.bubble")
            })
            .accessibilityIdentifier("clip.menu.generate_captions")

            Divider()

            transitionMenu

            Divider()
            Button(String(localized: "clip.menu.finder", defaultValue: "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([clip.url])
            }
            .accessibilityIdentifier("clip.menu.finder")

            Button(action: { onRelink?() }, label: {
                Label(String(localized: "clip.menu.relink", defaultValue: "Relink Clip..."), systemImage: "link.badge.plus")
            })
            .accessibilityIdentifier("clip.menu.relink")

            Divider()
            Button(role: .destructive, action: { onDeleteFile?() }, label: {
                Label(String(localized: "clip.menu.delete_disk", defaultValue: "Delete from Disk..."), systemImage: "trash.slash")
            })
            .accessibilityIdentifier("clip.menu.delete_disk")
        }
    }

    private var transitionMenu: some View {
        Menu {
            ForEach(TransitionType.allCases) { transitionType in
                Button {
                    onSetTransition?(transitionType)
                } label: {
                    HStack {
                        Image(systemName: transitionType.icon)
                        Text(transitionType.displayName)
                        if clip.transition?.type == transitionType {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if let transition = clip.transition {
                Label(String(localized: "clip.menu.transition.active", defaultValue: "Transition") + ": \(transition.type.displayName)", systemImage: "rectangle.2.swap")
            } else {
                Label(String(localized: "clip.menu.transition.add", defaultValue: "Add Transition"), systemImage: "rectangle.2.swap")
            }
        }
    }
}
