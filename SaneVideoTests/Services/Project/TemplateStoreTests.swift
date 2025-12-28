//
//  TemplateStoreTests.swift
//  SaneVideoTests
//
//  Tests for CustomTemplate model and TemplateStore persistence
//

import AVFoundation
import XCTest

@testable import SaneVideo

final class TemplateStoreTests: XCTestCase {

    // MARK: - CustomTemplate Model Tests

    func testCustomTemplateInitialization() {
        let template = CustomTemplate(
            name: "Test Template",
            description: "A test template",
            icon: "film",
            color: "blue",
            aspectRatio: CGSize(width: 16, height: 9)
        )

        XCTAssertFalse(template.id.uuidString.isEmpty)
        XCTAssertEqual(template.name, "Test Template")
        XCTAssertEqual(template.description, "A test template")
        XCTAssertEqual(template.icon, "film")
        XCTAssertEqual(template.color, "blue")
        XCTAssertEqual(template.aspectRatio, CGSize(width: 16, height: 9))
    }

    func testCustomTemplateEquality() {
        let id = UUID()
        let template1 = CustomTemplate(
            id: id,
            name: "Template",
            description: "Desc",
            icon: "film",
            color: "red",
            aspectRatio: CGSize(width: 16, height: 9)
        )
        let template2 = CustomTemplate(
            id: id,
            name: "Template",
            description: "Desc",
            icon: "film",
            color: "red",
            aspectRatio: CGSize(width: 16, height: 9)
        )
        let template3 = CustomTemplate(
            name: "Different",
            description: "Different",
            icon: "camera",
            color: "blue",
            aspectRatio: CGSize(width: 4, height: 3)
        )

        XCTAssertEqual(template1, template2, "Templates with same ID should be equal")
        XCTAssertNotEqual(template1, template3, "Templates with different IDs should not be equal")
    }

    func testCustomTemplateHashable() {
        let template1 = CustomTemplate(name: "T1", description: "", icon: "film", color: "red", aspectRatio: CGSize(width: 16, height: 9))
        let template2 = CustomTemplate(name: "T2", description: "", icon: "film", color: "blue", aspectRatio: CGSize(width: 16, height: 9))

        var set = Set<CustomTemplate>()
        set.insert(template1)
        set.insert(template2)
        set.insert(template1)  // Duplicate

        XCTAssertEqual(set.count, 2, "Set should contain only unique templates")
    }

    func testCustomTemplateCodable() throws {
        let original = CustomTemplate(
            name: "Encoded Template",
            description: "Test encoding",
            icon: "video",
            color: "purple",
            aspectRatio: CGSize(width: 9, height: 16),
            exportSettings: SaneExportSettings(
                codec: .h264,
                resolution: .hd1080,
                bitrate: 10_000_000,
                frameRate: 30.0
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CustomTemplate.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.icon, original.icon)
        XCTAssertEqual(decoded.color, original.color)
        XCTAssertEqual(decoded.aspectRatio, original.aspectRatio)
        XCTAssertEqual(decoded.exportSettings.resolution, original.exportSettings.resolution)
    }

    func testCustomTemplateAvailableIcons() {
        XCTAssertFalse(CustomTemplate.availableIcons.isEmpty, "Should have available icons")
        XCTAssertTrue(CustomTemplate.availableIcons.contains("star.fill"))
        XCTAssertTrue(CustomTemplate.availableIcons.contains("film.stack.fill"))
    }

    func testCustomTemplateAvailableColors() {
        XCTAssertFalse(CustomTemplate.availableColors.isEmpty, "Should have available colors")
        XCTAssertTrue(CustomTemplate.availableColors.contains("blue"))
        XCTAssertTrue(CustomTemplate.availableColors.contains("red"))
    }

    func testCustomTemplateAspectRatioString() {
        let template = CustomTemplate(
            name: "Test",
            aspectRatio: CGSize(width: 16, height: 9)
        )
        XCTAssertEqual(template.aspectRatioString, "16:9")

        let verticalTemplate = CustomTemplate(
            name: "Vertical",
            aspectRatio: CGSize(width: 9, height: 16)
        )
        XCTAssertEqual(verticalTemplate.aspectRatioString, "9:16")
    }

    // MARK: - TemplateStore Tests

    func testTemplateStoreInitialization() async {
        let store = TemplateStore()

        // Store should initialize without crashing
        let templates = await store.getAllTemplates()
        XCTAssertNotNil(templates, "Templates array should not be nil")
    }

    func testTemplateStoreSaveAndLoad() async throws {
        let store = TemplateStore()

        // Create a unique template for this test
        let testId = UUID()
        let template = CustomTemplate(
            id: testId,
            name: "Test Save \(testId.uuidString.prefix(8))",
            description: "Testing save functionality",
            icon: "film",
            color: "green",
            aspectRatio: CGSize(width: 16, height: 9)
        )

        // Save
        try await store.saveTemplate(template)

        // Load and verify
        let loaded = await store.getAllTemplates()
        let found = loaded.contains { $0.id == testId }
        XCTAssertTrue(found, "Saved template should be found in loaded templates")

        // Cleanup
        try await store.deleteTemplate(template)
    }

    func testTemplateStoreDelete() async throws {
        let store = TemplateStore()

        let testId = UUID()
        let template = CustomTemplate(
            id: testId,
            name: "To Delete",
            description: "Will be deleted",
            icon: "trash",
            color: "red",
            aspectRatio: CGSize(width: 16, height: 9)
        )

        // Save first
        try await store.saveTemplate(template)

        // Verify it exists
        var templates = await store.getAllTemplates()
        XCTAssertTrue(templates.contains { $0.id == testId }, "Template should exist after save")

        // Delete
        try await store.deleteTemplate(template)

        // Verify deletion
        templates = await store.getAllTemplates()
        XCTAssertFalse(templates.contains { $0.id == testId }, "Template should not exist after delete")
    }

    func testTemplateStoreUpdateExisting() async throws {
        let store = TemplateStore()

        let testId = UUID()
        let original = CustomTemplate(
            id: testId,
            name: "Original Name",
            description: "Original",
            icon: "film",
            color: "blue",
            aspectRatio: CGSize(width: 16, height: 9)
        )

        // Save original
        try await store.saveTemplate(original)

        // Update with same ID
        let updated = CustomTemplate(
            id: testId,
            name: "Updated Name",
            description: "Updated",
            icon: "video",
            color: "red",
            aspectRatio: CGSize(width: 9, height: 16)
        )
        try await store.saveTemplate(updated)

        // Load and verify update
        let templates = await store.getAllTemplates()
        let found = templates.first { $0.id == testId }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Updated Name")
        XCTAssertEqual(found?.color, "red")

        // Cleanup
        try await store.deleteTemplate(updated)
    }
}
