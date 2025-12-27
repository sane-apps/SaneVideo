//
//  ProjectStateUtilitiesTests.swift
//  SaneVideoTests
//
//  Tests for ProjectState+Utilities: transactions, cancellation, relinking, text-based editing
//

import CoreMedia
import XCTest

@testable import SaneVideo

final class ProjectStateUtilitiesTests: XCTestCase {

    var projectState: ProjectState!

    @MainActor
    override func setUp() {
        super.setUp()
        projectState = ProjectState()
        projectState.startNewProject()
        // Add a default video track for tests
        projectState.addTrack(type: .video, name: "Video Track 1")
    }

    override func tearDown() {
        projectState = nil
        super.tearDown()
    }

    // MARK: - Transaction Tests

    @MainActor
    func testBeginTransaction() {
        let transactionId = projectState.beginTransaction()

        XCTAssertNotNil(transactionId, "Transaction ID should not be nil")
        XCTAssertTrue(projectState.isValidTransaction(transactionId), "Transaction should be valid")
        XCTAssertTrue(projectState.isProcessing, "Should be processing with active transaction")
        XCTAssertEqual(projectState.activeTransactionCount, 1, "Should have 1 active transaction")

        projectState.endTransaction(transactionId)
    }

    @MainActor
    func testEndTransaction() {
        let transactionId = projectState.beginTransaction()
        XCTAssertTrue(projectState.isProcessing)

        projectState.endTransaction(transactionId)

        XCTAssertFalse(projectState.isValidTransaction(transactionId), "Transaction should be invalid after ending")
        XCTAssertFalse(projectState.isProcessing, "Should not be processing after transaction ends")
        XCTAssertEqual(projectState.activeTransactionCount, 0, "Should have 0 active transactions")
    }

    @MainActor
    func testMultipleTransactions() {
        let tx1 = projectState.beginTransaction()
        let tx2 = projectState.beginTransaction()
        let tx3 = projectState.beginTransaction()

        XCTAssertEqual(projectState.activeTransactionCount, 3, "Should have 3 active transactions")
        XCTAssertTrue(projectState.isProcessing)

        projectState.endTransaction(tx1)
        XCTAssertEqual(projectState.activeTransactionCount, 2)
        XCTAssertTrue(projectState.isProcessing, "Should still be processing with remaining transactions")

        projectState.endTransaction(tx2)
        projectState.endTransaction(tx3)
        XCTAssertFalse(projectState.isProcessing, "Should stop processing when all transactions end")
    }

    @MainActor
    func testCancelAllTransactions() {
        _ = projectState.beginTransaction()
        _ = projectState.beginTransaction()
        XCTAssertEqual(projectState.activeTransactionCount, 2)

        projectState.cancelAllTransactions()

        XCTAssertEqual(projectState.activeTransactionCount, 0, "All transactions should be cancelled")
        XCTAssertFalse(projectState.isProcessing)
    }

    @MainActor
    func testCancelSpecificTransaction() {
        let tx1 = projectState.beginTransaction()
        let tx2 = projectState.beginTransaction()

        projectState.cancelTransaction(tx1)

        XCTAssertFalse(projectState.isValidTransaction(tx1), "Cancelled transaction should be invalid")
        XCTAssertTrue(projectState.isValidTransaction(tx2), "Other transaction should still be valid")
        XCTAssertEqual(projectState.activeTransactionCount, 1)

        projectState.endTransaction(tx2)
    }

    @MainActor
    func testTransactionProgress() {
        let transactionId = projectState.beginTransaction()

        projectState.updateTransactionProgress(transactionId, progress: 0.5)
        XCTAssertEqual(projectState.getTransactionProgress(transactionId) ?? -1, 0.5, accuracy: 0.01)

        projectState.updateTransactionProgress(transactionId, progress: 1.0)
        XCTAssertEqual(projectState.getTransactionProgress(transactionId) ?? -1, 1.0, accuracy: 0.01)

        // Test clamping
        projectState.updateTransactionProgress(transactionId, progress: 1.5)
        XCTAssertEqual(projectState.getTransactionProgress(transactionId) ?? -1, 1.0, accuracy: 0.01, "Progress should be clamped to 1.0")

        projectState.updateTransactionProgress(transactionId, progress: -0.5)
        XCTAssertEqual(projectState.getTransactionProgress(transactionId) ?? -1, 0.0, accuracy: 0.01, "Progress should be clamped to 0.0")

        projectState.endTransaction(transactionId)
    }

    @MainActor
    func testShouldBlockOperation() {
        // No transaction - should not block
        XCTAssertFalse(projectState.shouldBlockOperation(), "Should not block when not processing")

        let transactionId = projectState.beginTransaction()

        // Processing active - should block without valid transaction
        XCTAssertTrue(projectState.shouldBlockOperation(), "Should block when processing without transaction ID")

        // With valid transaction ID - should not block
        XCTAssertFalse(projectState.shouldBlockOperation(transactionId: transactionId), "Should not block with valid transaction ID")

        // With invalid transaction ID - should block
        let fakeId = UUID()
        XCTAssertTrue(projectState.shouldBlockOperation(transactionId: fakeId), "Should block with invalid transaction ID")

        projectState.endTransaction(transactionId)
    }

    // MARK: - Cancellation Tests

    @MainActor
    func testCancelProcessing() async {
        _ = projectState.beginTransaction()
        _ = projectState.beginTransaction()

        await projectState.cancelProcessing()

        XCTAssertFalse(projectState.isProcessing, "Should not be processing after cancellation")
        XCTAssertEqual(projectState.activeTransactionCount, 0)
    }

    @MainActor
    func testCancelTransactionById() async {
        let tx1 = projectState.beginTransaction()
        let tx2 = projectState.beginTransaction()

        await projectState.cancelTransactionById(tx1)

        XCTAssertFalse(projectState.isValidTransaction(tx1))
        XCTAssertTrue(projectState.isValidTransaction(tx2))

        projectState.endTransaction(tx2)
    }

    // MARK: - Track Management Tests

    @MainActor
    func testAddVideoTrack() {
        let initialCount = projectState.currentProject?.timeline.tracks.count ?? 0

        projectState.addTrack(type: .video, name: "Test Video Track")

        let newCount = projectState.currentProject?.timeline.tracks.count ?? 0
        XCTAssertEqual(newCount, initialCount + 1, "Should have one more track")

        let addedTrack = projectState.currentProject?.timeline.tracks.last
        XCTAssertEqual(addedTrack?.name, "Test Video Track")
        XCTAssertEqual(addedTrack?.type, .video)
    }

    @MainActor
    func testAddAudioTrack() {
        projectState.addTrack(type: .audio)

        let audioTracks = projectState.currentProject?.timeline.tracks.filter { $0.type == .audio }
        XCTAssertGreaterThan(audioTracks?.count ?? 0, 0, "Should have at least one audio track")
    }

    @MainActor
    func testAddOverlayTrack() {
        projectState.addTrack(type: .overlay)

        let overlayTracks = projectState.currentProject?.timeline.tracks.filter { $0.type == .overlay }
        XCTAssertGreaterThan(overlayTracks?.count ?? 0, 0, "Should have at least one overlay track")
    }

    @MainActor
    func testDeleteTrack() {
        // Add a second track first
        projectState.addTrack(type: .video, name: "Track to Delete")

        guard let project = projectState.currentProject,
              let trackToDelete = project.timeline.tracks.last else {
            XCTFail("Should have a track to delete")
            return
        }

        let countBefore = project.timeline.tracks.count

        projectState.deleteTrack(trackToDelete)

        let countAfter = projectState.currentProject?.timeline.tracks.count ?? 0
        XCTAssertEqual(countAfter, countBefore - 1, "Should have one less track")
    }

    @MainActor
    func testCannotDeleteLastTrack() {
        // Get down to one track
        while let project = projectState.currentProject,
              project.timeline.tracks.count > 1,
              let track = project.timeline.tracks.last {
            projectState.deleteTrack(track)
        }

        guard let project = projectState.currentProject,
              let lastTrack = project.timeline.tracks.first else {
            XCTFail("Should have at least one track")
            return
        }

        XCTAssertEqual(project.timeline.tracks.count, 1)

        projectState.deleteTrack(lastTrack)

        // Should still have one track
        XCTAssertEqual(projectState.currentProject?.timeline.tracks.count, 1, "Should not delete the last track")
    }

    @MainActor
    func testToggleTrackMute() {
        guard let project = projectState.currentProject,
              let track = project.timeline.tracks.first else {
            XCTFail("Should have a track")
            return
        }

        let initialMuteState = track.isMuted

        projectState.toggleTrackMute(track)

        let newMuteState = projectState.currentProject?.timeline.tracks.first?.isMuted
        XCTAssertNotEqual(newMuteState, initialMuteState, "Mute state should be toggled")
    }

    @MainActor
    func testToggleTrackLock() {
        guard let project = projectState.currentProject,
              let track = project.timeline.tracks.first else {
            XCTFail("Should have a track")
            return
        }

        let initialLockState = track.isLocked

        projectState.toggleTrackLock(track)

        let newLockState = projectState.currentProject?.timeline.tracks.first?.isLocked
        XCTAssertNotEqual(newLockState, initialLockState, "Lock state should be toggled")
    }

    // MARK: - Timeline Validation Tests

    @MainActor
    func testValidateTimelineState() {
        guard let project = projectState.currentProject else {
            XCTFail("Should have a project")
            return
        }

        let isValid = projectState.validateTimelineState(project.timeline)
        XCTAssertTrue(isValid, "New project timeline should be valid")
    }

    @MainActor
    func testRecalculateStartTimes() {
        guard var project = projectState.currentProject else {
            XCTFail("Should have a project")
            return
        }

        // This just verifies it doesn't crash on an empty timeline
        projectState.recalculateStartTimes(in: &project.timeline)

        // Timeline should still be valid
        XCTAssertTrue(projectState.validateTimelineState(project.timeline))
    }
}
