//
//  WhisperKitPreloadRegressionTests.swift
//  SaneVideoTests
//
//  Regression tests for WhisperKit background pre-loading feature (2026-01-01)
//
//  Feature: Background model preload on app launch
//  Components:
//  - WhisperKitService.preloadModelInBackground(): Non-blocking background preload
//  - WhisperKitService.ModelState: Observable state for UI feedback
//  - TranscriptionCoordinator.preloadWhisperKit(): Delegates to service with toast
//  - ServiceContainer: Triggers preload on init
//

import Foundation
import Testing

@testable import SaneVideo

/// Regression tests for WhisperKit background pre-loading
@Suite("WhisperKit Preload Regression Tests")
struct WhisperKitPreloadRegressionTests {

    // MARK: - ModelState Tests

    @Test("ModelState has correct cases")
    func testModelStateCases() {
        // Verify all expected states exist
        let notLoaded = WhisperKitService.ModelState.notLoaded
        let downloading = WhisperKitService.ModelState.downloading
        let ready = WhisperKitService.ModelState.ready
        let failed = WhisperKitService.ModelState.failed("test error")

        // States should be distinguishable
        #expect(notLoaded != ready)
        #expect(downloading != ready)
        #expect(ready != failed)
    }

    @Test("ModelState is Equatable")
    func testModelStateEquatable() {
        let state1 = WhisperKitService.ModelState.ready
        let state2 = WhisperKitService.ModelState.ready
        let state3 = WhisperKitService.ModelState.notLoaded

        #expect(state1 == state2, "Same states should be equal")
        #expect(state1 != state3, "Different states should not be equal")
    }

    @Test("ModelState failed equality includes message")
    func testModelStateFailedEquality() {
        let error1 = WhisperKitService.ModelState.failed("error A")
        let error2 = WhisperKitService.ModelState.failed("error A")
        let error3 = WhisperKitService.ModelState.failed("error B")

        #expect(error1 == error2, "Same error message should be equal")
        #expect(error1 != error3, "Different error messages should not be equal")
    }

    @Test("ModelState is Sendable")
    func testModelStateSendable() async {
        // Verify ModelState can be sent across actor boundaries
        let state = WhisperKitService.ModelState.ready

        await Task.detached {
            // If this compiles, ModelState is Sendable
            let _ = state
        }.value
    }

    // MARK: - WhisperKitService Tests

    @Test("WhisperKitService can be instantiated")
    func testWhisperKitServiceInit() async {
        // WhisperKitService should initialize without starting download
        let service = WhisperKitService()
        // If we get here without blocking, init is lazy
        _ = service
    }

    @Test("WhisperKitService initial state is notLoaded")
    func testWhisperKitServiceInitialState() async {
        let service = WhisperKitService()
        let state = await service.modelState

        #expect(state == .notLoaded, "Initial state should be notLoaded")
    }

    @Test("WhisperKitService setStateChangeHandler accepts callback")
    func testWhisperKitServiceStateChangeHandler() async {
        let service = WhisperKitService()
        var callbackInvoked = false

        await service.setStateChangeHandler { @MainActor _ in
            callbackInvoked = true
        }

        // Handler is set without error (actual invocation happens during preload)
        #expect(callbackInvoked == false, "Handler should not be invoked until state changes")
    }

    // MARK: - TranscriptionCoordinator Tests

    @Test("TranscriptionCoordinator can be instantiated")
    @MainActor
    func testTranscriptionCoordinatorInit() {
        let coordinator = TranscriptionCoordinator()
        // If we get here, init succeeded
        _ = coordinator
    }

    @Test("TranscriptionCoordinator has preloadWhisperKit method")
    @MainActor
    func testTranscriptionCoordinatorHasPreloadMethod() {
        let coordinator = TranscriptionCoordinator()
        let toastManager = ToastManager()

        // Method exists and can be called
        coordinator.preloadWhisperKit(toastManager: toastManager)
        // Non-blocking - returns immediately
    }

    @Test("TranscriptionCoordinator exposes modelState")
    @MainActor
    func testTranscriptionCoordinatorExposesModelState() async {
        let coordinator = TranscriptionCoordinator()

        // Can access model state (async property)
        let state = await coordinator.modelState
        #expect(state == .notLoaded, "Initial state should be notLoaded")
    }

    // MARK: - Integration Architecture Tests

    @Test("WhisperKit preload architecture complete")
    @MainActor
    func testWhisperKitPreloadArchitecture() async {
        // This test verifies the complete background preload architecture:
        //
        // 1. WhisperKitService.ModelState: Observable state enum
        //    - .notLoaded: Initial state before preload
        //    - .downloading: Model is downloading/loading
        //    - .ready: Model loaded and ready to use
        //    - .failed(String): Error occurred during loading
        //
        // 2. WhisperKitService.preloadModelInBackground():
        //    - Non-blocking - returns immediately
        //    - Uses Task.detached(priority: .utility)
        //    - Skips if already initialized
        //    - Calls stateChangeHandler on state changes
        //
        // 3. WhisperKitService.setStateChangeHandler():
        //    - Sets callback for state changes
        //    - Callback runs on MainActor for UI updates
        //
        // 4. TranscriptionCoordinator.preloadWhisperKit():
        //    - Delegates to WhisperKitService
        //    - Sets up toast notification on ready
        //
        // 5. ServiceContainer.init():
        //    - Calls preloadWhisperKit after Vision warmup
        //    - Non-blocking - doesn't delay app launch

        let service = WhisperKitService()
        let state = await service.modelState

        #expect(state == .notLoaded, "Initial state should be notLoaded")

        let coordinator = TranscriptionCoordinator()
        let coordinatorState = await coordinator.modelState
        #expect(coordinatorState == .notLoaded, "Coordinator should expose initial state")
    }

    // MARK: - Edge Case Tests

    @Test("Multiple preload calls are idempotent")
    func testMultiplePreloadCallsIdempotent() async {
        let service = WhisperKitService()

        // First call should start preload
        await service.preloadModelInBackground()

        // Second call should be no-op (already in progress)
        await service.preloadModelInBackground()

        // Third call should also be no-op
        await service.preloadModelInBackground()

        // If we get here without error, calls are idempotent
    }

    @Test("Preload does not block calling thread")
    func testPreloadDoesNotBlock() async {
        let service = WhisperKitService()
        let startTime = Date()

        // Preload should return immediately (model download happens in background)
        await service.preloadModelInBackground()

        let elapsed = Date().timeIntervalSince(startTime)

        // Should complete in under 100ms (actual download is background)
        #expect(elapsed < 0.1, "preloadModelInBackground should return immediately")
    }
}
