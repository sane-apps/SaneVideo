//
//  TemplateBrowserSheet.swift
//  SaneVideo
//
//  Browse, create, and manage export templates
//

import AVFoundation
import SwiftUI

/// Sheet for browsing and managing export templates
struct TemplateBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: ((CustomTemplate) -> Void)?
    let currentSettings: SaneExportSettings?
    let currentAspectRatio: CGSize?

    @State private var templates: [CustomTemplate] = []
    @State private var isLoading = true
    @State private var showingCreateSheet = false
    @State private var selectedTemplate: CustomTemplate?
    @State private var templateToDelete: CustomTemplate?
    @State private var showDeleteConfirmation = false

    private let templateStore = TemplateStore()

    init(
        onSelect: ((CustomTemplate) -> Void)? = nil,
        currentSettings: SaneExportSettings? = nil,
        currentAspectRatio: CGSize? = nil
    ) {
        self.onSelect = onSelect
        self.currentSettings = currentSettings
        self.currentAspectRatio = currentAspectRatio
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: String(localized: "templates.header.title", defaultValue: "Template Library"),
                subtitle: String(localized: "templates.header.subtitle", defaultValue: "Save and reuse export settings"),
                dismissAction: { dismiss() },
                accessibilityID: "templates.sheet.close"
            )

            Divider()

            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        builtInSection
                        Divider()
                        customSection
                    }
                    .padding(20)
                }
            }

            Divider()
            footer
        }
        .frame(width: 550, height: 600)
        .subtleGlass(radius: 12)
        .task { await loadTemplates() }
        .sheet(isPresented: $showingCreateSheet) {
            TemplateEditorSheet(
                template: nil,
                currentSettings: currentSettings,
                currentAspectRatio: currentAspectRatio
            ) { newTemplate in
                Task {
                    try? await templateStore.saveTemplate(newTemplate)
                    await loadTemplates()
                }
            }
        }
        .alert(
            String(localized: "templates.delete.title", defaultValue: "Delete Template?"),
            isPresented: $showDeleteConfirmation,
            presenting: templateToDelete
        ) { template in
            Button(String(localized: "templates.action.delete", defaultValue: "Delete"), role: .destructive) {
                Task {
                    try? await templateStore.deleteTemplate(template)
                    await loadTemplates()
                }
            }
            Button(String(localized: "templates.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: { template in
            Text(String(localized: "templates.delete.message", defaultValue: "This will permanently delete '\(template.name)'."))
        }
    }

    // MARK: - Sections

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(String(localized: "templates.loading", defaultValue: "Loading templates..."))
                .font(.caption)
                .foregroundStyle(Color.stone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "templates.builtin.header", defaultValue: "Built-in Templates"),
                systemImage: "star.fill"
            )
            .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ProjectTemplate.allTemplates, id: \.id) { template in
                    BuiltInTemplateCard(template: template) {
                        // Convert to CustomTemplate for selection
                        let custom = CustomTemplate(
                            name: template.name,
                            description: template.description,
                            icon: template.icon,
                            color: template.color,
                            aspectRatio: template.aspectRatio,
                            exportSettings: template.defaultExportSettings,
                            captionStyle: template.defaultCaptionStyle
                        )
                        onSelect?(custom)
                        dismiss()
                    }
                }
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    String(localized: "templates.custom.header", defaultValue: "My Templates"),
                    systemImage: "folder.fill"
                )
                .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    showingCreateSheet = true
                } label: {
                    Label(
                        String(localized: "templates.action.create", defaultValue: "New Template"),
                        systemImage: "plus.circle.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("templates.action.create")
            }

            if templates.isEmpty {
                emptyCustomView
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(templates) { template in
                        CustomTemplateCard(
                            template: template,
                            onSelect: {
                                onSelect?(template)
                                dismiss()
                            },
                            onDelete: {
                                templateToDelete = template
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyCustomView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(Color.stone)

            Text(String(localized: "templates.empty.title", defaultValue: "No custom templates yet"))
                .font(.subheadline)

            Text(String(localized: "templates.empty.subtitle", defaultValue: "Create templates from your current project settings"))
                .font(.caption)
                .foregroundStyle(Color.stone)
                .multilineTextAlignment(.center)

            if currentSettings != nil {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label(
                        String(localized: "templates.action.create_from_current", defaultValue: "Create from Current"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("templates.action.create_from_current")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(String(localized: "templates.action.done", defaultValue: "Done")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("templates.action.done")
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func loadTemplates() async {
        templates = await templateStore.loadTemplates()
        isLoading = false
    }
}

// MARK: - Built-in Template Card

private struct BuiltInTemplateCard: View {
    let template: ProjectTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundStyle(colorFromString(template.color))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.caption.weight(.semibold))
                    Text(template.description)
                        .font(.caption2)
                        .foregroundStyle(Color.stone)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("templates.builtin.\(template.name.lowercased())")
    }

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "black": return .primary
        case "green": return .green
        case "orange": return .orange
        default: return .accentColor
        }
    }
}

// MARK: - Custom Template Card

private struct CustomTemplateCard: View {
    let template: CustomTemplate
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundStyle(colorFromString(template.color))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.caption.weight(.semibold))
                    Text("\(template.resolutionString) • \(template.codecString)")
                        .font(.caption2)
                        .foregroundStyle(Color.stone)
                }

                Spacer()

                if isHovered {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("templates.custom.\(template.id.uuidString)")
    }

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "teal": return .teal
        default: return .accentColor
        }
    }
}

// MARK: - Template Editor Sheet

private struct TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: CustomTemplate?
    let currentSettings: SaneExportSettings?
    let currentAspectRatio: CGSize?
    let onSave: (CustomTemplate) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedIcon: String = "star.fill"
    @State private var selectedColor: String = "blue"

    init(
        template: CustomTemplate?,
        currentSettings: SaneExportSettings?,
        currentAspectRatio: CGSize?,
        onSave: @escaping (CustomTemplate) -> Void
    ) {
        self.template = template
        self.currentSettings = currentSettings
        self.currentAspectRatio = currentAspectRatio
        self.onSave = onSave

        _name = State(initialValue: template?.name ?? "")
        _description = State(initialValue: template?.description ?? "")
        _selectedIcon = State(initialValue: template?.icon ?? "star.fill")
        _selectedColor = State(initialValue: template?.color ?? "blue")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: template == nil
                    ? String(localized: "templates.editor.create", defaultValue: "Create Template")
                    : String(localized: "templates.editor.edit", defaultValue: "Edit Template"),
                subtitle: String(localized: "templates.editor.subtitle", defaultValue: "Save current settings as template"),
                dismissAction: { dismiss() },
                accessibilityID: "templates.editor.close"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.name", defaultValue: "Name"))
                            .font(.subheadline.weight(.semibold))
                        TextField(
                            String(localized: "templates.editor.name.placeholder", defaultValue: "My Template"),
                            text: $name
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("templates.editor.name")
                    }

                    // Description field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.description", defaultValue: "Description"))
                            .font(.subheadline.weight(.semibold))
                        TextField(
                            String(localized: "templates.editor.description.placeholder", defaultValue: "Optional description..."),
                            text: $description
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("templates.editor.description")
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.icon", defaultValue: "Icon"))
                            .font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(CustomTemplate.availableIcons, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .frame(width: 36, height: 36)
                                        .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.color", defaultValue: "Color"))
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 8) {
                            ForEach(CustomTemplate.availableColors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(colorFromString(color))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color ? Color.white : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Settings preview
                    if let settings = currentSettings {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "templates.editor.settings", defaultValue: "Settings to Save"))
                                .font(.subheadline.weight(.semibold))

                            HStack(spacing: 16) {
                                Label(settings.resolution.displayName, systemImage: "rectangle.on.rectangle")
                                Label(codecName(settings.codec), systemImage: "film")
                                Label("\(Int(settings.frameRate)) fps", systemImage: "speedometer")
                            }
                            .font(.caption)
                            .foregroundStyle(Color.stone)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "templates.editor.cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "templates.editor.save", defaultValue: "Save Template")) {
                    saveTemplate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
                .accessibilityIdentifier("templates.editor.save")
            }
            .padding(16)
        }
        .frame(width: 400, height: 500)
        .subtleGlass(radius: 12)
    }

    private func saveTemplate() {
        let newTemplate = CustomTemplate(
            id: template?.id ?? UUID(),
            name: name,
            description: description,
            icon: selectedIcon,
            color: selectedColor,
            aspectRatio: currentAspectRatio ?? CGSize(width: 16, height: 9),
            exportSettings: currentSettings ?? SaneExportSettings(),
            captionStyle: "Classic"
        )
        onSave(newTemplate)
        dismiss()
    }

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "green": return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "teal": return .teal
        default: return .accentColor
        }
    }

    private func codecName(_ codec: AVVideoCodecType) -> String {
        switch codec {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .proRes422: return "ProRes"
        default: return "Unknown"
        }
    }
}

#Preview {
    TemplateBrowserSheet(
        onSelect: { _ in },
        currentSettings: SaneExportSettings(),
        currentAspectRatio: CGSize(width: 16, height: 9)
    )
}
