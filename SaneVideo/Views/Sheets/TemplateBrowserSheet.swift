import SwiftUI

/// Saved export settings the user can reuse: apply, save current, rename, delete.
struct TemplateBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: ((CustomTemplate) -> Void)?
    let currentSettings: SaneExportSettings?
    let currentAspectRatio: CGSize?

    @State private var templates: [CustomTemplate] = []
    @State private var newName = ""
    @State private var renaming: CustomTemplate?
    @State private var renameText = ""

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
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Templates")
                .font(.title2.weight(.semibold))
            Text("Save export settings you use often and apply them in one click.")

            if templates.isEmpty {
                Text("No saved templates yet.")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    ForEach(templates) { template in
                        row(template)
                    }
                }
                .frame(minHeight: 220)
            }

            if let currentSettings {
                HStack {
                    TextField("Name for current settings", text: $newName)
                    Button("Save Current Settings") { save(currentSettings) }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { templates = await templateStore.loadTemplates() }
        .alert("Rename Template", isPresented: Binding(get: { renaming != nil }, set: {
            if !$0 {
                renaming = nil
            }
        })) {
            TextField("Name", text: $renameText)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ template: CustomTemplate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.headline)
                Text("\(template.resolutionString) · \(template.codecString)")
            }
            Spacer()
            if onSelect != nil {
                Button("Apply") {
                    onSelect?(template)
                    dismiss()
                }
            }
        }
        .contextMenu {
            Button("Rename") {
                renameText = template.name
                renaming = template
            }
            Button("Delete", role: .destructive) { delete(template) }
        }
    }

    private func save(_ settings: SaneExportSettings) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        Task {
            _ = try? await templateStore.createFromProject(
                name: name,
                description: "",
                exportSettings: settings,
                aspectRatio: currentAspectRatio ?? CGSize(width: 16, height: 9),
                captionStyle: "Classic"
            )
            newName = ""
            templates = await templateStore.loadTemplates()
        }
    }

    private func rename() {
        guard var template = renaming else { return }
        template.name = renameText
        renaming = nil
        Task {
            try? await templateStore.saveTemplate(template)
            templates = await templateStore.loadTemplates()
        }
    }

    private func delete(_ template: CustomTemplate) {
        Task {
            try? await templateStore.deleteTemplate(template)
            templates = await templateStore.loadTemplates()
        }
    }
}
