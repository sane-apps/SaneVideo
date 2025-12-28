//
//  iCloudSyncTests.swift
//  SaneVideoTests
//
//  Tests for iCloud Sync types and services
//

import XCTest

@testable import SaneVideo

final class iCloudSyncTests: XCTestCase {

    // MARK: - SyncStatus Tests

    func testSyncStatusValues() {
        XCTAssertEqual(SyncStatus.local.rawValue, "Local Only")
        XCTAssertEqual(SyncStatus.syncing.rawValue, "Syncing...")
        XCTAssertEqual(SyncStatus.synced.rawValue, "Synced")
        XCTAssertEqual(SyncStatus.conflict.rawValue, "Conflict")
        XCTAssertEqual(SyncStatus.error.rawValue, "Sync Error")
    }

    func testSyncStatusIcons() {
        XCTAssertEqual(SyncStatus.local.icon, "externaldrive")
        XCTAssertEqual(SyncStatus.syncing.icon, "arrow.triangle.2.circlepath")
        XCTAssertEqual(SyncStatus.synced.icon, "checkmark.icloud")
        XCTAssertEqual(SyncStatus.conflict.icon, "exclamationmark.icloud")
        XCTAssertEqual(SyncStatus.error.icon, "xmark.icloud")
    }

    func testSyncStatusCodable() throws {
        let original = SyncStatus.synced
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncStatus.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - SyncEvent Tests

    func testSyncEventInitialization() {
        let projectId = UUID()
        let timestamp = Date()

        let event = SyncEvent(
            projectId: projectId,
            status: .syncing,
            message: "Uploading files...",
            timestamp: timestamp
        )

        XCTAssertEqual(event.projectId, projectId)
        XCTAssertEqual(event.status, .syncing)
        XCTAssertEqual(event.message, "Uploading files...")
        XCTAssertEqual(event.timestamp, timestamp)
    }

    func testSyncEventWithNilMessage() {
        let projectId = UUID()

        let event = SyncEvent(
            projectId: projectId,
            status: .synced,
            message: nil,
            timestamp: Date()
        )

        XCTAssertNil(event.message)
    }

    // MARK: - SyncInfo Tests

    func testSyncInfoInitialization() {
        let projectId = UUID()
        let date = Date()

        let info = SyncInfo(
            projectId: projectId,
            lastSynced: date,
            deviceName: "MacBook Pro",
            version: 5
        )

        XCTAssertEqual(info.projectId, projectId)
        XCTAssertEqual(info.lastSynced, date)
        XCTAssertEqual(info.deviceName, "MacBook Pro")
        XCTAssertEqual(info.version, 5)
    }

    func testSyncInfoFormattedLastSynced() {
        // Test with recent date (should format as relative time)
        let recentDate = Date()
        let recentInfo = SyncInfo(
            projectId: UUID(),
            lastSynced: recentDate,
            deviceName: "Mac",
            version: 1
        )
        XCTAssertFalse(recentInfo.formattedLastSynced.isEmpty)

        // Test with older date
        let oldDate = Date().addingTimeInterval(-3600 * 24)  // 1 day ago
        let oldInfo = SyncInfo(
            projectId: UUID(),
            lastSynced: oldDate,
            deviceName: "Mac",
            version: 1
        )
        XCTAssertFalse(oldInfo.formattedLastSynced.isEmpty)
    }

    func testSyncInfoCodable() throws {
        let original = SyncInfo(
            projectId: UUID(),
            lastSynced: Date(),
            deviceName: "iMac",
            version: 3
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncInfo.self, from: data)

        XCTAssertEqual(decoded.projectId, original.projectId)
        XCTAssertEqual(decoded.deviceName, original.deviceName)
        XCTAssertEqual(decoded.version, original.version)
    }

    // MARK: - SyncError Tests

    func testSyncErrorDescriptions() {
        let errors: [SyncError] = [
            .iCloudNotAvailable,
            .projectNotFound,
            .syncFailed(NSError(domain: "test", code: 1)),
            .conflictUnresolved,
            .downloadFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    func testSyncErrorICloudNotAvailable() {
        let error = SyncError.iCloudNotAvailable
        XCTAssertTrue(error.errorDescription!.contains("iCloud"))
    }

    func testSyncErrorSyncFailedWrapsUnderlyingError() {
        let underlyingError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test failure"])
        let error = SyncError.syncFailed(underlyingError)
        XCTAssertTrue(error.errorDescription!.contains("Test failure"))
    }

    // MARK: - MediaAssetReference Tests

    func testMediaAssetReferenceInitialization() {
        let reference = MediaAssetReference(
            originalFilename: "video.mp4",
            relativePath: "Media/abc123/video.mp4",
            fileSize: 1024 * 1024 * 100,  // 100MB
            checksum: "abc123def456"
        )

        XCTAssertEqual(reference.originalFilename, "video.mp4")
        XCTAssertEqual(reference.relativePath, "Media/abc123/video.mp4")
        XCTAssertEqual(reference.fileSize, 1024 * 1024 * 100)
        XCTAssertEqual(reference.checksum, "abc123def456")
    }

    func testMediaAssetReferenceOptionalFields() {
        let reference = MediaAssetReference(
            originalFilename: "audio.m4a",
            relativePath: "Media/audio.m4a"
        )

        XCTAssertEqual(reference.originalFilename, "audio.m4a")
        XCTAssertNil(reference.fileSize)
        XCTAssertNil(reference.checksum)
    }

    func testMediaAssetReferenceEquatable() {
        let ref1 = MediaAssetReference(
            originalFilename: "video.mp4",
            relativePath: "Media/video.mp4",
            fileSize: 1000,
            checksum: "abc"
        )
        let ref2 = MediaAssetReference(
            originalFilename: "video.mp4",
            relativePath: "Media/video.mp4",
            fileSize: 1000,
            checksum: "abc"
        )
        let ref3 = MediaAssetReference(
            originalFilename: "other.mp4",
            relativePath: "Media/other.mp4"
        )

        XCTAssertEqual(ref1, ref2)
        XCTAssertNotEqual(ref1, ref3)
    }

    func testMediaAssetReferenceCodable() throws {
        let original = MediaAssetReference(
            originalFilename: "test.mov",
            relativePath: "Media/uuid/test.mov",
            fileSize: 5000,
            checksum: "sha256hash"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MediaAssetReference.self, from: data)

        XCTAssertEqual(decoded.originalFilename, original.originalFilename)
        XCTAssertEqual(decoded.relativePath, original.relativePath)
        XCTAssertEqual(decoded.fileSize, original.fileSize)
        XCTAssertEqual(decoded.checksum, original.checksum)
    }

    // MARK: - MediaAssetError Tests

    func testMediaAssetErrorDescriptions() {
        let errors: [MediaAssetError] = [
            .iCloudNotAvailable,
            .downloadTimeout,
            .checksumMismatch,
            .fileNotFound,
            .copyFailed
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    func testMediaAssetErrorSpecificMessages() {
        XCTAssertTrue(MediaAssetError.iCloudNotAvailable.errorDescription!.contains("iCloud"))
        XCTAssertTrue(MediaAssetError.downloadTimeout.errorDescription!.lowercased().contains("timed out"))
        XCTAssertTrue(MediaAssetError.checksumMismatch.errorDescription!.lowercased().contains("integrity"))
    }

    // MARK: - SyncManager Tests

    func testSyncManagerInitialization() async {
        let manager = SyncManager()
        XCTAssertNotNil(manager)
    }

    func testSyncManagerDefaultStatus() async {
        let manager = SyncManager()
        let randomId = UUID()

        let status = await manager.getStatus(for: randomId)
        XCTAssertEqual(status, .local, "Unknown project should have local status")
    }

    func testSyncManagerEnableDisable() async {
        let manager = SyncManager()

        await manager.setSyncEnabled(true)
        let enabled = await manager.isSyncCurrentlyEnabled()
        XCTAssertTrue(enabled)

        await manager.setSyncEnabled(false)
        let disabled = await manager.isSyncCurrentlyEnabled()
        XCTAssertFalse(disabled)
    }

    // MARK: - MediaAssetManager Tests

    func testMediaAssetManagerInitialization() async {
        let manager = MediaAssetManager()
        XCTAssertNotNil(manager)
    }

    func testMediaAssetManagerRelativePath() async {
        let manager = MediaAssetManager()
        let projectDir = URL(fileURLWithPath: "/Users/test/Projects/MyProject")

        // File inside project directory
        let insideURL = URL(fileURLWithPath: "/Users/test/Projects/MyProject/Media/video.mp4")
        let insidePath = await manager.relativePath(from: insideURL, projectDir: projectDir)
        XCTAssertEqual(insidePath, "Media/video.mp4")

        // File outside project directory
        let outsideURL = URL(fileURLWithPath: "/Users/test/Videos/external.mov")
        let outsidePath = await manager.relativePath(from: outsideURL, projectDir: projectDir)
        XCTAssertEqual(outsidePath, "Media/external.mov")
    }

    func testMediaAssetManagerResolveNonExistentAsset() async {
        let manager = MediaAssetManager()
        let projectDir = URL(fileURLWithPath: "/Users/test/Projects/MyProject")

        // Resolve non-existent file should return nil
        let resolved = await manager.resolveAsset(relativePath: "Media/nonexistent.mp4", projectDir: projectDir)
        XCTAssertNil(resolved, "Non-existent file should resolve to nil")
    }
}
