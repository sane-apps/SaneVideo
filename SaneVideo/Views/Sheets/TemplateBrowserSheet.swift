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
                icon: "square.stack.3d.up.fill",
                dismissAction: { dismiss() },
                accessibilityID: "templates.sheet.close"
            )

            Divider()

            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureCallout(
                            title: "Reusable demo recipes",
                            message: "Templates save export settings, caption defaults, presentation presets, and demo-pack behavior together.",
                            icon: "folder.badge.plus"
                        )
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
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
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
                .saneReadableSupportText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                String(localized: "templates.builtin.header", defaultValue: "Built-in Templates"),
                systemImage: "star.fill"
            )
            .saneReadableSectionTitle()

            HelperText(
                text: "Start here if you want a ready-made product-demo format without tuning every export setting yourself.",
                icon: "wand.and.stars"
            )

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
                            captionStyle: template.defaultCaptionStyle,
                            presentationPreset: template.defaultPresentationPreset,
                            demoPackSettings: template.defaultPresentationPreset.recommendedDemoPackSettings,
                            publishMetadata: .default(for: template.name)
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
                .saneReadableSectionTitle()

                Spacer()

                Button {
                    showingCreateSheet = true
                } label: {
                    Label(
                        String(localized: "templates.action.create", defaultValue: "New Template"),
                        systemImage: "plus.circle.fill"
                    )
                    .font(Theme.Typography.meta)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("templates.action.create")
            }

            HelperText(
                text: "Save your current setup here when you find a combination you want to reuse across launches, tutorials, or support demos.",
                icon: "square.and.arrow.down.fill"
            )

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
                .saneReadableBodyStrong()

            Text(String(localized: "templates.empty.subtitle", defaultValue: "Create templates from your current project settings"))
                .saneReadableSupportText()
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

                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .saneReadableBodyStrong()
                    Text(template.description)
                        .saneReadableSupportText()
                        .lineLimit(2)
                    FeatureBadge(
                        label: template.defaultPresentationPreset.displayName,
                        icon: template.defaultPresentationPreset.icon,
                        accent: colorFromString(template.color)
                    )
                }

                Spacer()
            }
            .padding(12)
            .sanePanel(radius: 12, accent: colorFromString(template.color))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("templates.builtin.\(template.name.lowercased())")
        .help(template.description)
    }

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .teal
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

                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .saneReadableBodyStrong()
                    Text("\(template.resolutionString) • \(template.codecString)")
                        .saneReadableSupportText()
                    FeatureBadge(
                        label: template.presentationPreset.displayName,
                        icon: template.presentationPreset.icon,
                        accent: colorFromString(template.color)
                    )
                }

                Spacer()

                if isHovered {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: Theme.Typography.fontSizeSM, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .sanePanel(radius: 12, accent: colorFromString(template.color))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("templates.custom.\(template.id.uuidString)")
        .help(template.description.isEmpty ? "Custom template" : template.description)
    }

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .teal
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
                icon: "square.and.arrow.down.on.square",
                dismissAction: { dismiss() },
                accessibilityID: "templates.editor.close"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FeatureCallout(
                        title: "Save your house style",
                        message: "A template preserves the current export setup so you can reuse it across future demos with one click.",
                        icon: "checkmark.seal.fill"
                    )

                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.name", defaultValue: "Name"))
                            .saneReadableLabel()
                        TextField(
                            String(localized: "templates.editor.name.placeholder", defaultValue: "My Template"),
                            text: $name
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("templates.editor.name")
                        HelperText(text: "Use a clear name like Launch Vertical, Product Walkthrough, or Support How-To.", icon: "tag.fill")
                    }

                    // Description field
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.description", defaultValue: "Description"))
                            .saneReadableLabel()
                        TextField(
                            String(localized: "templates.editor.description.placeholder", defaultValue: "Optional description..."),
                            text: $description
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("templates.editor.description")
                        HelperText(text: "Describe when to use this template so it is obvious later.", icon: "text.bubble.fill")
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "templates.editor.icon", defaultValue: "Icon"))
                            .saneReadableLabel()

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
                            .saneReadableLabel()

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
                                .saneReadableLabel()

                            HStack(spacing: 16) {
                                Label(settings.resolution.displayName, systemImage: "rectangle.on.rectangle")
                                Label(codecName(settings.codec), systemImage: "film")
                                Label("\(Int(settings.frameRate)) fps", systemImage: "speedometer")
                            }
                            .saneReadableSupportText()

                            HelperText(text: "The current export settings are what this template will reapply later.", icon: "gearshape.2.fill")
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
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
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
            captionStyle: "Classic",
            presentationPreset: inferredPresentationPreset(),
            demoPackSettings: inferredPresentationPreset().recommendedDemoPackSettings,
            publishMetadata: .default(for: name)
        )
        onSave(newTemplate)
        dismiss()
    }

    private func inferredPresentationPreset() -> PresentationPreset {
        let ratio = currentAspectRatio ?? CGSize(width: 16, height: 9)

        if abs(ratio.width - 9) < 0.1 && abs(ratio.height - 16) < 0.1 {
            return .verticalDemo
        }

        if abs(ratio.width - 1) < 0.1 && abs(ratio.height - 1) < 0.1 {
            return .squareTeaser
        }

        return .productWalkthrough
    }

    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "purple": return .teal
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
