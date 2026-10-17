// Saved export templates persist to disk and come back in a fresh store.
// Every store uses its own temp directory, never ~/Movies.

import AVFoundation
import Foundation
@testable import SaneVideo
import Testing

@Suite("Template Store")
struct TemplateStoreTests {
    private func withTempDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemplateStoreTests_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func makeTemplate(id: UUID = UUID(), name: String = "Vertical 1080p") -> CustomTemplate {
        CustomTemplate(
            id: id,
            name: name,
            description: "Shorts export",
            icon: "film",
            color: "green",
            aspectRatio: CGSize(width: 9, height: 16),
            exportSettings: SaneExportSettings(
                codec: .h264,
                resolution: .hd1080,
                bitrate: 10_000_000,
                frameRate: 30.0
            ),
            captionStyle: "TikTok"
        )
    }

    @Test("A saved template loads back from disk with its settings in a new store")
    func saveAndReload() async throws {
        try await withTempDirectory { directory in
            let template = makeTemplate()
            try await TemplateStore(directory: directory).saveTemplate(template)

            let loaded = await TemplateStore(directory: directory).getAllTemplates()

            let found = try #require(loaded.first { $0.id == template.id })
            #expect(found.name == "Vertical 1080p")
            #expect(found.description == "Shorts export")
            #expect(found.aspectRatio == CGSize(width: 9, height: 16))
            #expect(found.captionStyle == "TikTok")
            #expect(found.exportSettings.codec == .h264)
            #expect(found.exportSettings.resolution == .hd1080)
            #expect(found.exportSettings.bitrate == 10_000_000)
            #expect(found.exportSettings.frameRate == 30.0)
        }
    }

    @Test("Deleting a template removes it from disk")
    func deleteRemovesFromDisk() async throws {
        try await withTempDirectory { directory in
            let store = TemplateStore(directory: directory)
            let template = makeTemplate()
            try await store.saveTemplate(template)

            try await store.deleteTemplate(template)

            #expect(await store.getAllTemplates().isEmpty)
            #expect(await TemplateStore(directory: directory).getAllTemplates().isEmpty)
        }
    }

    @Test("Saving with an existing id overwrites the template instead of adding one")
    func saveOverwritesExisting() async throws {
        try await withTempDirectory { directory in
            let store = TemplateStore(directory: directory)
            let id = UUID()
            try await store.saveTemplate(makeTemplate(id: id, name: "Original Name"))
            try await store.saveTemplate(makeTemplate(id: id, name: "Updated Name"))

            let reloaded = await TemplateStore(directory: directory).getAllTemplates()

            #expect(reloaded.map(\.name) == ["Updated Name"])
        }
    }

    @Test("Duplicating a template saves a copy with a new id and a 'Copy' name")
    func duplicateCreatesCopy() async throws {
        try await withTempDirectory { directory in
            let store = TemplateStore(directory: directory)
            let original = makeTemplate()
            try await store.saveTemplate(original)

            let copy = try await store.duplicateTemplate(original)

            #expect(copy.id != original.id)
            #expect(copy.name == "Vertical 1080p Copy")
            #expect(copy.exportSettings.resolution == original.exportSettings.resolution)
            let reloaded = await TemplateStore(directory: directory).getAllTemplates()
            #expect(Set(reloaded.map(\.id)) == [original.id, copy.id])
        }
    }

    @Test("aspectRatioString formats width:height")
    func aspectRatioString() {
        #expect(CustomTemplate(name: "Wide", aspectRatio: CGSize(width: 16, height: 9)).aspectRatioString == "16:9")
        #expect(CustomTemplate(name: "Tall", aspectRatio: CGSize(width: 9, height: 16)).aspectRatioString == "9:16")
    }
}
