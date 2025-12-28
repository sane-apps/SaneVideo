//
//  ExportPresetPicker.swift
//  SaneVideo
//
//  Dropdown picker for selecting export templates in the export sheet
//

import SwiftUI

/// Picker for selecting export templates (built-in or custom)
struct ExportPresetPicker: View {
    @Binding var exportSettings: SaneExportSettings
    @Binding var selectedPreset: ExportPreset?

    @State private var customTemplates: [CustomTemplate] = []
    @State private var showTemplateBrowser = false
    @State private var selectedCustomTemplate: CustomTemplate?

    private let templateStore = TemplateStore()

    var body: some View {
        HStack(spacing: 8) {
            // Templates button
            Button {
                showTemplateBrowser = true
            } label: {
                Label(
                    String(localized: "export.templates.browse", defaultValue: "Templates"),
                    systemImage: "folder.fill"
                )
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("export.templates.browse")

            // Quick template picker (if custom templates exist)
            if !customTemplates.isEmpty {
                Menu {
                    Section(String(localized: "export.templates.recent", defaultValue: "Recent Templates")) {
                        ForEach(customTemplates.prefix(5)) { template in
                            Button {
                                applyTemplate(template)
                            } label: {
                                Label(template.name, systemImage: template.icon)
                            }
                        }
                    }

                    Divider()

                    Button {
                        showTemplateBrowser = true
                    } label: {
                        Label(
                            String(localized: "export.templates.view_all", defaultValue: "View All Templates..."),
                            systemImage: "folder"
                        )
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .accessibilityIdentifier("export.templates.quick_menu")
            }

            // Current template indicator
            if let template = selectedCustomTemplate {
                HStack(spacing: 4) {
                    Image(systemName: template.icon)
                        .font(.caption)
                    Text(template.name)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .task {
            customTemplates = await templateStore.loadTemplates()
        }
        .sheet(isPresented: $showTemplateBrowser) {
            TemplateBrowserSheet(
                onSelect: { template in
                    applyTemplate(template)
                },
                currentSettings: exportSettings,
                currentAspectRatio: nil
            )
        }
    }

    private func applyTemplate(_ template: CustomTemplate) {
        selectedCustomTemplate = template
        exportSettings = template.exportSettings
        selectedPreset = .custom // Mark as custom since we're using a template
    }
}

// MARK: - Template Quick Apply Button

/// Button to quickly apply a template with one click
struct TemplateQuickApplyButton: View {
    let template: CustomTemplate
    let isSelected: Bool
    let onApply: () -> Void

    var body: some View {
        Button(action: onApply) {
            VStack(spacing: 4) {
                Image(systemName: template.icon)
                    .font(.system(size: 16))
                Text(template.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("export.template.quick.\(template.id.uuidString)")
    }
}

#Preview {
    @Previewable @State var settings = SaneExportSettings()
    @Previewable @State var preset: ExportPreset?

    ExportPresetPicker(
        exportSettings: $settings,
        selectedPreset: $preset
    )
    .padding()
}
