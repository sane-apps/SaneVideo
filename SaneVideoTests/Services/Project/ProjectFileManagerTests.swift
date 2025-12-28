//
//  ProjectFileManagerTests.swift
//  SaneVideoTests
//
//  Unit tests for ProjectFileManager file operations.
//

import AVFoundation
import XCTest

@testable import SaneVideo

final class ProjectFileManagerTests: XCTestCase {

    var sut: ProjectFileManagerProtocolMock!

    override func setUp() async throws {
        sut = ProjectFileManagerProtocolMock()
    }

    override func tearDown() {
        sut = nil
    }

    // MARK: - Load Clip Tests

    func testLoadClip_CallsHandler() async throws {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/test_video.mp4")
        let expectedClip = VideoClip(
            url: testURL,
            duration: CMTime(seconds: 30, preferredTimescale: 600)
        )

        sut.loadClipHandler = { url in
            XCTAssertEqual(url, testURL)
            return expectedClip
        }

        // Act
        let result = try await sut.loadClip(from: testURL)

        // Assert
        XCTAssertEqual(result.url, expectedClip.url)
        XCTAssertEqual(sut.loadClipCallCount, 1)
    }

    func testLoadClip_CanThrowError() async {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/nonexistent.mp4")
        let expectedError = NSError(domain: "ProjectFileManager", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "File not found"
        ])

        sut.loadClipHandler = { _ in
            throw expectedError
        }

        // Act & Assert
        do {
            _ = try await sut.loadClip(from: testURL)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual((error as NSError).code, 404)
        }
    }

    func testLoadClip_RecordsURL() async throws {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/specific_file.mp4")
        sut.loadClipHandler = { url in
            return VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))
        }

        // Act
        _ = try await sut.loadClip(from: testURL)

        // Assert
        XCTAssertEqual(sut.loadClipArgValues.first, testURL)
    }

    // MARK: - Bookmark Tests

    func testCreateBookmark_CallsHandler() throws {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let expectedData = Data([0x01, 0x02, 0x03])

        sut.createBookmarkHandler = { url in
            XCTAssertEqual(url, testURL)
            return expectedData
        }

        // Act
        let result = try sut.createBookmark(for: testURL)

        // Assert
        XCTAssertEqual(result, expectedData)
        XCTAssertEqual(sut.createBookmarkCallCount, 1)
    }

    func testCreateBookmark_CanThrowError() {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let expectedError = NSError(domain: "Bookmark", code: 500, userInfo: nil)

        sut.createBookmarkHandler = { _ in
            throw expectedError
        }

        // Act & Assert
        do {
            _ = try sut.createBookmark(for: testURL)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual((error as NSError).code, 500)
        }
    }

    func testResolveBookmark_CallsHandler() throws {
        // Arrange
        let bookmarkData = Data([0x01, 0x02, 0x03])
        let expectedURL = URL(fileURLWithPath: "/tmp/resolved.mp4")

        sut.resolveBookmarkHandler = { data in
            XCTAssertEqual(data, bookmarkData)
            return (expectedURL, false)
        }

        // Act
        let (url, isStale) = try sut.resolveBookmark(data: bookmarkData)

        // Assert
        XCTAssertEqual(url, expectedURL)
        XCTAssertFalse(isStale)
        XCTAssertEqual(sut.resolveBookmarkCallCount, 1)
    }

    func testResolveBookmark_ReturnsStaleFlag() throws {
        // Arrange
        let bookmarkData = Data([0x01, 0x02, 0x03])
        let expectedURL = URL(fileURLWithPath: "/tmp/stale.mp4")

        sut.resolveBookmarkHandler = { _ in
            return (expectedURL, true)
        }

        // Act
        let (_, isStale) = try sut.resolveBookmark(data: bookmarkData)

        // Assert
        XCTAssertTrue(isStale)
    }

    // MARK: - Delete File Tests

    func testDeleteFile_CallsHandler() async throws {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/to_delete.mp4")
        var deleteCalled = false

        sut.deleteFileHandler = { url in
            XCTAssertEqual(url, testURL)
            deleteCalled = true
        }

        // Act
        try await sut.deleteFile(at: testURL)

        // Assert
        XCTAssertTrue(deleteCalled)
        XCTAssertEqual(sut.deleteFileCallCount, 1)
    }

    func testDeleteFile_CanThrowError() async {
        // Arrange
        let testURL = URL(fileURLWithPath: "/tmp/protected.mp4")
        let expectedError = NSError(domain: "FileManager", code: 403, userInfo: nil)

        sut.deleteFileHandler = { _ in
            throw expectedError
        }

        // Act & Assert
        do {
            try await sut.deleteFile(at: testURL)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertEqual((error as NSError).code, 403)
        }
    }

    // MARK: - Hydrate Project Tests

    func testHydrateProject_CallsHandler() {
        // Arrange
        let project = VideoProject()
        var hydrateCalled = false

        sut.hydrateProjectHandler = { p in
            hydrateCalled = true
            XCTAssertEqual(p.id, project.id)
            return (p, false)
        }

        // Act
        let (_, needsSave) = sut.hydrateProject(project)

        // Assert
        XCTAssertTrue(hydrateCalled)
        XCTAssertFalse(needsSave)
        XCTAssertEqual(sut.hydrateProjectCallCount, 1)
    }

    func testHydrateProject_ReturnsNeedsSaveTrue() {
        // Arrange
        let project = VideoProject()

        sut.hydrateProjectHandler = { p in
            return (p, true)
        }

        // Act
        let (_, needsSave) = sut.hydrateProject(project)

        // Assert
        XCTAssertTrue(needsSave)
    }

    func testHydrateProject_RecordsArgument() {
        // Arrange
        let project = VideoProject()
        sut.hydrateProjectHandler = { p in (p, false) }

        // Act
        _ = sut.hydrateProject(project)

        // Assert
        XCTAssertEqual(sut.hydrateProjectArgValues.first?.id, project.id)
    }

    // MARK: - Security Scope Tests

    func testEnterSecurityScope_CallsHandler() {
        // Arrange
        let project = VideoProject()
        var scopeCalled = false

        sut.enterSecurityScopeHandler = { p in
            scopeCalled = true
            XCTAssertEqual(p.id, project.id)
            return ProjectFileManager.SecurityScopeSession(urls: [])
        }

        // Act
        let session = sut.enterSecurityScope(for: project)

        // Assert
        XCTAssertTrue(scopeCalled)
        XCTAssertNotNil(session)
        XCTAssertEqual(sut.enterSecurityScopeCallCount, 1)
    }

    // MARK: - Multiple Operations Tests

    func testMultipleClipLoads_TracksCallCount() async throws {
        // Arrange
        sut.loadClipHandler = { url in
            return VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))
        }

        let urls = (1...5).map { URL(fileURLWithPath: "/tmp/clip\($0).mp4") }

        // Act
        for url in urls {
            _ = try await sut.loadClip(from: url)
        }

        // Assert
        XCTAssertEqual(sut.loadClipCallCount, 5)
        XCTAssertEqual(sut.loadClipArgValues.count, 5)
    }
}
