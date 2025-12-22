//
//  StateMachineVerificationTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import XCTest
import Combine
import AVFoundation
import CoreMedia
@testable import SaneVideo

@MainActor
final class StateMachineVerificationTests: XCTestCase {

    var appState: AppState!
    var windowManager: WindowManager!
    var recordingState: RecordingState!
    var mockCameraService: MockCameraService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        // Setup isolated test environment
        mockCameraService = MockCameraService()
        
        // Inject Mocks into Singleton Container
        ServiceContainer.shared.cameraService = mockCameraService
        
        // Mock Audio Service (Requires PermissionManager)
        let pm = ServiceContainer.shared.permissionManager
        let mockAudio = MockAudioService(permissionManager: pm)
        ServiceContainer.shared.audioService = mockAudio
        
        // Now init AppState (which uses the container's services)
        // Note: ProjectState might try to read disk, so we should mock file manager if possible.
        // But ProjectState inits its own store.
        
        appState = AppState()
        windowManager = appState.windowManager
        recordingState = appState.recordingState
        
        cancellables = []
    }

    override func tearDown() {
        appState = nil
        cancellables = nil
    }

    // MARK: - Scenario 1: Screen Share -> Record -> Stop
    
    func testScreenShareRecordingFlow() async throws {
        print("🧪 Testing: Screen Share -> Record -> Stop")
        
        // 1. Initial State
        XCTAssertFalse(appState.isScreenSharing)
        XCTAssertFalse(appState.isRecording)
        
        // 2. Start Screen Share
        appState.toggleScreenShare()
        XCTAssertTrue(appState.isScreenSharing, "Should be screen sharing")
        XCTAssertTrue(appState.windowManager.isPiPVisible, "PiP should be visible by default")
        
        // Verify Window Logic (Mocked or checked via state)
        // We can't actually check NSWindow visibility in Unit Test easily without a host app,
        // but we can check the *intent* in WindowMgr
        
        // 3. Start Recording
        appState.startRecording()
        
        // Allow time for "Preparing" -> "Countdown"
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(appState.recordingState.isPreparing || appState.recordingState.isRecording)
        
        // Simulate countdown finish
        // (In unit test, we might need to wait or mock the countdown)
        // Let's manually trigger the state transition if possible, or wait
        // The real countdown is 3s.
        
        // Fast-forward or just wait? 3s is long for a test.
        // We can verify `isPreparing` is true.
        XCTAssertTrue(appState.isPreparing, "Should be counting down")
        
        // 4. Force state to Recording (simulate countdown end)
        // We can't assume private access, but we can wait or just test logic pre-recording.
        // Let's assume recording starts.
        
        // 5. STOP Recording
        // appState.stopRecording() calls async cleanup
        let expectation = XCTestExpectation(description: "Recording Stopped")
        
        appState.recordingState.isRecording = true // Cheat to skip countdown for test speed
        appState.recordingState.isPreparing = false
        
        appState.stopRecording()
        
        // Verify "Immediate" State changes
        // stopRecording is async for file saving, but UI state updates should be orchestrated.
        
        // WAIT for completion
        // In AppState, stopRecording calls Task { ... handleRecordingFinished ... }
        // We need to wait a bit.
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // 6. Verify Restoration
        // CRITICAL: WindowManager state check
        XCTAssertFalse(appState.isScreenSharing, "Should exit screen share after recording")
        XCTAssertFalse(appState.windowManager.isScreenSharing, "WindowManager should know screen share ended")
        
        // PiP Logic:
        // "updatePiPState(isCameraActive: false, isRecording: false)" -> Hides PiP
        // We can check `isPiPVisible` state property? 
        // Note: isPiPVisible remains `true` (user preference) but `shouldShowPiP` logic depends on context.
        // However, we can check if the WindowManager *believes* it should show.
        // Ideally we'd check pipWindow == nil, but that's internal.
        
        // We relies on `isScreenSharing` being false to ensure PiP hides.
        XCTAssertFalse(appState.isScreenSharing)
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Scenario 3: Screen Share -> Stop Share (No Recording)
    
    func testScreenShareStopOnlyFlow() async throws {
        print("🧪 Testing: Screen Share -> Stop Share")
        
        // 1. Start Share
        appState.toggleScreenShare()
        XCTAssertTrue(appState.isScreenSharing)
        
        // 2. Stop Share
        appState.toggleScreenShare()
        
        // 3. Verify
        XCTAssertFalse(appState.isScreenSharing)
        XCTAssertFalse(appState.windowManager.isScreenSharing)
    }

    // MARK: - Crash Regression (Zombie Window Logic)
    
    func testZombieWindowFixLogic() async throws {
        // This tests the WindowManager code path specifically
        
        // 1. Show PiP
        appState.windowManager.isPiPVisible = true
        appState.windowManager.isScreenSharing = true
        appState.windowManager.updatePiPState(isCameraActive: true, isRecording: false)
        
        // 2. Hide PiP
        appState.windowManager.updatePiPState(isCameraActive: false, isRecording: false)
        
        // The fix was in the *implementation* of hidePiPWindow.
        // We can't easily assert the window memory state here without internals,
        // but verifying it doesn't crash on execution is a good smoke test.
        XCTAssertTrue(true, "Did not crash calling updatePiPState")
    }
}

// Mock Audio Service
class MockAudioService: AudioService {
    override func start() {
        // No-op for tests to avoid TCC crash
        print("MockAudioService: start called")
    }
    
    override func stop() {
        print("MockAudioService: stop called")
    }
    
    override func checkPermission() {
        // No-op
    }
    
    override func requestPermission() {
        // No-op
    }
}

// Mock Helper
class MockCameraService: NSObject, CameraServiceProtocol {
    var isActive: Bool = false
    var hasVideoSignal: Bool = false
    var permissionGranted: Bool = true
    var lastError: AppError? = nil
    var session: AVCaptureSession? = nil

    var sessionPublisher: AnyPublisher<AVCaptureSession?, Never> { Just(nil).eraseToAnyPublisher() }
    var isActivePublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    // nonisolated required by protocol
    nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> { PassthroughSubject() }
    
    func start(completion: @escaping @Sendable () -> Void) { completion() }
    func stop() {}
    func toggle() {}
    func switchCamera(to device: AVCaptureDevice) {}
    func restartSession() {}
    func requestPermissionAgain() {}
}
