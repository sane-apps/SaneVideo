//
//  ModeSwitcherView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct ModeSwitcherView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 12) {
            // Mode Switcher Tabs
            HStack(spacing: 0) {
                // Recording Mode Tab
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appState.switchToRecording()
                    }
                }, label: {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 14, weight: .semibold))
                        Text(String(localized: "mode.record", defaultValue: "Record"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(appState.appMode == .recording ? .white : .secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        ZStack {
                            if appState.appMode == .recording {
                                Capsule()
                                    .fill(Theme.Colors.destructive)
                                    .matchedGeometryEffect(id: "ActiveTab", in: animationNamespace)
                            }
                        }
                    )
                    .contentShape(Rectangle()) // Ensure entire area is clickable
                })
                .buttonStyle(.plain)
                .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "mode.help.recording", defaultValue: "Switch to recording mode"), key: "n", modifiers: [.command]))
                .accessibilityIdentifier("RecordTabButton")

                // Editing Mode Tab
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appState.switchToEditing()
                    }
                }, label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                            .font(.system(size: 14, weight: .semibold))
                        Text(String(localized: "mode.edit", defaultValue: "Edit"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(appState.appMode == .editing ? .white : .secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        ZStack {
                            if appState.appMode == .editing {
                                Capsule()
                                    .fill(Theme.Colors.accent)
                                    .matchedGeometryEffect(id: "ActiveTab", in: animationNamespace)
                            }
                        }
                    )
                    .contentShape(Rectangle()) // Ensure entire area is clickable
                })
                .buttonStyle(.plain)
                .help(String(localized: "mode.help.editing", defaultValue: "Switch to editing mode"))
                .accessibilityIdentifier("EditTabButton")
            }
            .padding(4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Center: Editable Project Name (only in Edit mode - naming happens after recording stops)
            if appState.appMode == .editing, let project = appState.projectState.currentProject {
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowRenameProjectDialog"), object: nil)
                }, label: {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                })
                .buttonStyle(.plain)
                .help(String(localized: "mode.help.rename_project", defaultValue: "Click to rename project"))
                .accessibilityIdentifier("modeswitcher.project_name")
            }

            Spacer()

            // Action Buttons - Only show in editing mode
            if appState.appMode == .editing {
                HStack(spacing: 8) {
                    // Import Button
                    Button(action: {
                        appState.importVideo()
                    }, label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text(String(localized: "mode.action.import", defaultValue: "Import"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.secondaryGradient) // Use Theme Gradient
                        )
                    })
                    .buttonStyle(.plain)
                    .keyboardShortcut("i", modifiers: [.command])
                    .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "mode.help.import", defaultValue: "Import Video"), key: "i", modifiers: [.command]))
                    .accessibilityIdentifier("ImportVideoButton")

                    // Export Button (Hero Action - Prominent)
                    Button(action: {
                        appState.showExportSheet = true
                    }, label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text(String(localized: "mode.action.export", defaultValue: "Export"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.accentGradient) // Use Theme Gradient
                        )
                        .shadow(color: Theme.Colors.accent.opacity(0.3), radius: 4, y: 2)
                    })
                    .buttonStyle(.plain)
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(appState.projectState.currentProject == nil)
                    .help(KeyboardShortcutHelper.helpWithShortcut(String(localized: "mode.help.export", defaultValue: "Export Video"), key: "e", modifiers: [.command]))
                    .accessibilityIdentifier("ExportButton")
                }
            }
        }
        .padding(.horizontal, 24) // Added padding to prevent being cramped to the edge
    }

    @Namespace private var animationNamespace
}
