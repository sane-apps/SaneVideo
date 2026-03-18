//
//  TemplateStore.swift
//  SaneVideo
//
//  Actor for persisting and managing user-created export templates
//  Storage: ~/Movies/SaneVideo/Templates/*.svtemplate
//

import Foundation

/// Actor for managing custom export templates
actor TemplateStore {
    // MARK: - Properties

    private var templates: [CustomTemplate] = []
    private var isLoaded = false

    private var templatesDirectory: URL {
        let moviesDir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        return moviesDir
            .appendingPathComponent("SaneVideo")
            .appendingPathComponent("Templates")
    }

    // MARK: - Public API

    /// Load all templates from disk
    func loadTemplates() async -> [CustomTemplate] {
        if isLoaded {
            return templates
        }

        do {
            try ensureDirectoryExists()
            let files = try FileManager.default.contentsOfDirectory(
                at: templatesDirectory,
                includingPropertiesForKeys: nil
            )

            templates = files
                .filter { $0.pathExtension == "svtemplate" }
                .compactMap { url -> CustomTemplate? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(CustomTemplate.self, from: data)
                }
                .sorted { $0.modifiedAt > $1.modifiedAt }

            isLoaded = true
            AppLogger.general.info("Loaded \(templates.count) custom templates")
        } catch {
            AppLogger.general.error("Failed to load templates: \(error)")
        }

        return templates
    }

    /// Save a template (new or update)
    func saveTemplate(_ template: CustomTemplate) async throws {
        try ensureDirectoryExists()

        var mutableTemplate = template
        mutableTemplate.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(mutableTemplate)

        let fileURL = templateFileURL(for: mutableTemplate)
        try data.write(to: fileURL)

        // Update in-memory cache
        if let index = templates.firstIndex(where: { $0.id == mutableTemplate.id }) {
            templates[index] = mutableTemplate
        } else {
            templates.insert(mutableTemplate, at: 0)
        }

        AppLogger.general.info("Saved template: \(mutableTemplate.name)")
    }

    /// Delete a template
    func deleteTemplate(_ template: CustomTemplate) async throws {
        let fileURL = templateFileURL(for: template)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        templates.removeAll { $0.id == template.id }
        AppLogger.general.info("Deleted template: \(template.name)")
    }

    /// Get all templates (loads if needed)
    func getAllTemplates() async -> [CustomTemplate] {
        if !isLoaded {
            return await loadTemplates()
        }
        return templates
    }

    /// Create template from current project settings
    func createFromProject(
        name: String,
        description: String,
        exportSettings: SaneExportSettings,
        aspectRatio: CGSize,
        captionStyle: String,
        presentationPreset: PresentationPreset = .productWalkthrough,
        speakerNotes: SpeakerNotes = .init(),
        chapterMarkers: [ChapterMarker] = [],
        demoPackSettings: DemoPackSettings = .init(),
        publishMetadata: PublishMetadata = .init()
    ) async throws -> CustomTemplate {
        let template = CustomTemplate(
            name: name,
            description: description,
            aspectRatio: aspectRatio,
            exportSettings: exportSettings,
            captionStyle: captionStyle,
            presentationPreset: presentationPreset,
            speakerNotes: speakerNotes,
            chapterMarkers: chapterMarkers,
            demoPackSettings: demoPackSettings,
            publishMetadata: publishMetadata
        )

        try await saveTemplate(template)
        return template
    }

    /// Duplicate a template
    func duplicateTemplate(_ template: CustomTemplate) async throws -> CustomTemplate {
        var duplicate = template
        duplicate = CustomTemplate(
            name: "\(template.name) Copy",
            description: template.description,
            icon: template.icon,
            color: template.color,
            aspectRatio: template.aspectRatio,
            exportSettings: template.exportSettings,
            captionStyle: template.captionStyle,
            presentationPreset: template.presentationPreset,
            speakerNotes: template.speakerNotes,
            chapterMarkers: template.chapterMarkers,
            demoPackSettings: template.demoPackSettings,
            publishMetadata: template.publishMetadata
        )

        try await saveTemplate(duplicate)
        return duplicate
    }

    // MARK: - Private Helpers

    private func ensureDirectoryExists() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: templatesDirectory.path) {
            try fm.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
        }
    }

    private func templateFileURL(for template: CustomTemplate) -> URL {
        templatesDirectory.appendingPathComponent("\(template.id.uuidString).svtemplate")
    }
}

// MARK: - Protocol for Testing

protocol TemplateStoreProtocol: Actor {
    func loadTemplates() async -> [CustomTemplate]
    func saveTemplate(_ template: CustomTemplate) async throws
    func deleteTemplate(_ template: CustomTemplate) async throws
    func getAllTemplates() async -> [CustomTemplate]
}

extension TemplateStore: TemplateStoreProtocol {}
