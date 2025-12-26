//
//  ClipContextMenu.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import AppKit

/// Context menu for TimelineClipView
struct ClipContextMenu: View {
    let clip: VideoClip

    var onSplit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onRemoveSilence: (() -> Void)?
    var onRemoveFillers: (() -> Void)?
    var onGenerateCaptions: (() -> Void)?
    var onSmartCrop: ((CGFloat) -> Void)?
    var onAutoFrame: (() -> Void)?
    var onFindGestures: (() -> Void)?
    var onPrivacyBlur: (() -> Void)?
    var onFindHighlights: (() -> Void)?
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

            // MARK: - Audio Submenu
            Menu {
                Button(action: { onRemoveSilence?() }, label: {
                    Label(String(localized: "clip.menu.remove_silence", defaultValue: "Remove Silence (Sane Cut)"), systemImage: "waveform.path")
                })
                .accessibilityIdentifier("clip.menu.remove_silence")

                Button(action: { onRemoveFillers?() }, label: {
                    Label(String(localized: "clip.menu.remove_fillers", defaultValue: "Remove Filler Words"), systemImage: "text.badge.minus")
                })
                .disabled(clip.captions.isEmpty)
                .accessibilityIdentifier("clip.menu.remove_fillers")

                Button(action: {
                    onFindHighlights?()
                    AppLogger.project.info("Find Highlights requested for clip")
                }, label: {
                    Label(String(localized: "clip.menu.find_highlights", defaultValue: "Find Highlights"), systemImage: "hands.clap")
                })
                .accessibilityIdentifier("clip.menu.find_highlights")
            } label: {
                Label(String(localized: "clip.menu.audio", defaultValue: "Audio"), systemImage: "waveform")
            }

            // MARK: - Vision Submenu
            Menu {
                smartCropSubmenu
                Button(action: {
                    onAutoFrame?()
                    AppLogger.project.info("Auto-Frame requested for clip")
                }, label: {
                    Label(String(localized: "clip.menu.center_face", defaultValue: "Center Face"), systemImage: "person.crop.rectangle")
                })
                .accessibilityIdentifier("clip.menu.center_face")

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
                Label(String(localized: "clip.menu.vision", defaultValue: "Vision"), systemImage: "eye")
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

    private var smartCropSubmenu: some View {
        Menu {
            Button(action: {
                onSmartCrop?(9.0 / 16.0)
                AppLogger.project.info("Smart Crop 9:16 requested")
            }, label: {
                Label(String(localized: "clip.menu.smart_crop.9_16", defaultValue: "9:16 (TikTok/Reels)"), systemImage: "rectangle.portrait")
            })
            .accessibilityIdentifier("clip.menu.smart_crop.9_16")

            Button(action: {
                onSmartCrop?(1.0)
                AppLogger.project.info("Smart Crop 1:1 requested")
            }, label: {
                Label(String(localized: "clip.menu.smart_crop.1_1", defaultValue: "1:1 (Instagram)"), systemImage: "square")
            })
            .accessibilityIdentifier("clip.menu.smart_crop.1_1")

            Button(action: {
                onSmartCrop?(16.0 / 9.0)
                AppLogger.project.info("Smart Crop 16:9 requested")
            }, label: {
                Label(String(localized: "clip.menu.smart_crop.16_9", defaultValue: "16:9 (YouTube)"), systemImage: "rectangle")
            })
            .accessibilityIdentifier("clip.menu.smart_crop.16_9")

            Button(action: {
                onSmartCrop?(21.0 / 9.0)
                AppLogger.project.info("Smart Crop 21:9 requested")
            }, label: {
                Label(String(localized: "clip.menu.smart_crop.21_9", defaultValue: "21:9 (Cinematic)"), systemImage: "rectangle.ratio.16.to.9")
            })
            .accessibilityIdentifier("clip.menu.smart_crop.21_9")

        } label: {
            Label(String(localized: "clip.menu.smart_crop", defaultValue: "Smart Crop"), systemImage: "crop.rotate")
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
