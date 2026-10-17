//
//  RecordingEngineTests.swift
//  SaneVideoTests
//
//  RecordingEngine runs in test mode here (no camera, screen or file). These tests cover its state
//  guards and the A/V timestamp handling around source switches.
//
//  Fire-and-forget calls (switchSource, setMuted) enqueue a task on RecordingActor. A later await on
//  the same actor runs after that task's first step, so guard rejections need no wait. Switches that
//  complete after a main-actor hop are awaited with `eventually`.
//

import AVFoundation
import AudioToolbox
@testable import SaneVideo
import Testing

@Suite("Recording Engine Tests")
@MainActor
struct RecordingEngineTests {
    var sut: RecordingEngine {
        RecordingEngine()
    }

    // MARK: - Recording Lifecycle

    @Test("Start recording sets isRecording and keeps the initial source", arguments: [RecordingSource.camera, .screen])
    func startRecordingSetsFlag(source: RecordingSource) async throws {
        let engine = sut

        await engine.startRecording(initialSource: source)

        #expect(await engine.isRecording == true)
        #expect(await engine.currentSource == source)
        _ = await engine.stopRecording()
    }

    @Test("Stop recording clears isRecording")
    func stopRecordingClearsFlag() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)

        _ = await engine.stopRecording()

        #expect(await engine.isRecording == false)
    }

    @Test("Pause sets isPaused and resume clears it")
    func pauseAndResume() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)

        await engine.pauseRecording()
        #expect(await engine.isPaused == true)

        await engine.resumeRecording()
        #expect(await engine.isPaused == false)
        _ = await engine.stopRecording()
    }

    @Test("Pause does nothing when not recording")
    func pauseIgnoredWhenNotRecording() async throws {
        let engine = sut

        await engine.pauseRecording()

        #expect(await engine.isPaused == false)
    }

    @Test("Muted microphone writes no audio; unmuting resumes writing")
    func mutedMicrophoneWritesNoAudio() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)
        let writer = await makeActiveVideoWriterMock()
        await configureWriterState(engine, writer: writer, current: .camera)
        let coordinator = await engine.timeCoordinator
        let firstVideo = coordinator.processSampleTime(CMTime(seconds: 10, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(firstVideo.presentationTime)

        engine.setMuted(true)
        let sample105 = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 10.5, preferredTimescale: 48_000))
        await engine.processAudioSample(sample105)
        #expect(await engine.isMicMuted == true)
        #expect(await micWriteCallCount(writer) == 0)

        engine.setMuted(false)
        let sample106 = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 10.6, preferredTimescale: 48_000))
        await engine.processAudioSample(sample106)
        #expect(await micWriteCallCount(writer) == 1)

        _ = await engine.stopRecording()
    }

    @Test("Double stop is prevented")
    func doubleStopPrevented() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)

        async let stop1 = engine.stopRecording()
        async let stop2 = engine.stopRecording()
        _ = await (stop1, stop2)

        #expect(await engine.isRecording == false)
        #expect(await engine.isStopping == false)
    }

    @Test("Recording start resets time coordinator timing state")
    func startRecordingResetsTimeCoordinatorState() async throws {
        let engine = sut
        let coordinator = await engine.timeCoordinator
        coordinator.startTime = CMTime(seconds: 9, preferredTimescale: 600)
        coordinator.timeOffset = CMTime(seconds: 2, preferredTimescale: 600)
        coordinator.startTimeNeedsRecalibration = true

        await engine.startRecording(initialSource: .camera)

        #expect(coordinator.startTime == .zero)
        #expect(coordinator.timeOffset == .zero)
        #expect(coordinator.startTimeNeedsRecalibration == false)

        _ = await engine.stopRecording()
    }

    // MARK: - Guard Conditions

    @Test("Cannot start recording when already recording")
    func cannotStartWhenRecording() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)
        #expect(await engine.isRecording == true)

        await engine.startRecording(initialSource: .screen)

        #expect(await engine.isRecording == true)
        #expect(await engine.currentSource == .camera)
        _ = await engine.stopRecording()
    }

    @Test("isStopping blocks a new recording from starting")
    func isStoppingPreventsRestart() async throws {
        let engine = sut
        await setStopping(engine, true)

        await engine.startRecording(initialSource: .camera)

        #expect(await engine.isRecording == false)
        await setStopping(engine, false)
    }

    @Test("Screen recording without camera overlay skips camera start")
    func screenRecordingWithoutCameraOverlaySkipsCameraStart() async throws {
        let cameraService = CameraServiceProtocolMock()
        let screenRecorder = ScreenRecorderCallCountingMock()
        let audioService = MockAudioService(
            permissionManager: ServiceContainer.shared.permissionManager
        )
        let engine = RecordingEngine(
            cameraService: cameraService,
            audioService: audioService,
            screenRecorder: screenRecorder
        )

        await engine.startRecording(initialSource: .screen, includeCameraOverlay: false)

        #expect(cameraService.startCallCount == 0)
        #expect(await engine.isRecording == true)
        _ = await engine.stopRecording()
    }

    @Test("Microphone readiness helper times out when mic never becomes live")
    func microphoneReadinessTimesOut() async throws {
        let audioService = DelayedStartAudioService(
            permissionManager: ServiceContainer.shared.permissionManager,
            startDelayNanoseconds: nil
        )
        let engine = RecordingEngine(
            cameraService: CameraServiceProtocolMock(),
            audioService: audioService,
            screenRecorder: ScreenRecorderCallCountingMock()
        )

        audioService.start()

        let ready = await engine.waitForMicrophoneCaptureToStart(
            timeoutNanoseconds: 120_000_000,
            pollNanoseconds: 20_000_000,
            allowTestBypass: false
        )

        #expect(ready == false)
    }

    @Test("Microphone readiness helper succeeds when mic becomes live shortly after start")
    func microphoneReadinessSucceedsAfterDelayedStart() async throws {
        let audioService = DelayedStartAudioService(
            permissionManager: ServiceContainer.shared.permissionManager,
            startDelayNanoseconds: 40_000_000
        )
        let engine = RecordingEngine(
            cameraService: CameraServiceProtocolMock(),
            audioService: audioService,
            screenRecorder: ScreenRecorderCallCountingMock()
        )

        audioService.start()

        let ready = await engine.waitForMicrophoneCaptureToStart(
            timeoutNanoseconds: 2_000_000_000,
            pollNanoseconds: 20_000_000,
            allowTestBypass: false
        )

        #expect(ready == true)
    }

    @Test("Stop returns nil when not recording")
    func stopReturnsNilWhenNotRecording() async throws {
        let engine = sut

        let result = await engine.stopRecording()

        #expect(result == nil)
    }

    // MARK: - Source Switching

    @Test("Cannot switch source when not recording")
    func cannotSwitchWhenNotRecording() async throws {
        let engine = sut

        engine.switchSource(source: .screen)

        #expect(await engine.currentSource == .camera)
        #expect(await engine.isSwitching == false)
    }

    @Test("Switching to the current source is ignored")
    func cannotSwitchToSameSource() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)

        engine.switchSource(source: .camera)

        #expect(await engine.isSwitching == false)
        #expect(await engine.pendingSource == nil)
        #expect(await engine.currentSource == .camera)
        _ = await engine.stopRecording()
    }

    @Test("Switch source completes in both directions without leaving a timeout task armed")
    func testModeSourceSwitchesDoNotArmTimeoutTasks() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)

        engine.switchSource(source: .screen)
        #expect(try await eventually {
            let source = await engine.currentSource
            let switching = await engine.isSwitching
            return source == .screen && !switching
        })
        #expect(await engine.pendingSource == nil)
        #expect(engine.sourceSwitchTimeoutTask == nil)

        engine.switchSource(source: .camera)
        #expect(try await eventually {
            let source = await engine.currentSource
            let switching = await engine.isSwitching
            return source == .camera && !switching
        })
        #expect(await engine.pendingSource == nil)
        #expect(engine.sourceSwitchTimeoutTask == nil)

        _ = await engine.stopRecording()
    }

    @Test("A switch request is ignored while another switch is in progress")
    func concurrentSwitchRequestsBlocked() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)
        await configureSwitchState(engine, current: .camera, pending: .screen, needsRecalibration: true)

        engine.switchSource(source: .screen)

        #expect(await engine.currentSource == .camera)
        #expect(await engine.pendingSource == .screen)
        _ = await engine.stopRecording()
    }

    @Test("Cannot switch source while stopping")
    func cannotSwitchWhileStopping() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)
        await setStopping(engine, true)

        engine.switchSource(source: .screen)

        #expect(await engine.isSwitching == false)
        #expect(await engine.currentSource == .camera)
        await setStopping(engine, false)
        _ = await engine.stopRecording()
    }

    @Test("Pending camera frames do not complete screen to camera switch early")
    func pendingCameraFramesDoNotCompleteScreenToCameraSwitchEarly() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .screen)

        await configureSwitchState(
            engine,
            current: .screen,
            pending: .camera,
            needsRecalibration: true
        )

        let coordinator = await engine.timeCoordinator

        let sampleBuffer = try makeVideoSampleBuffer(
            presentationTime: CMTime(value: 600, timescale: 600)
        )

        await engine.processSample(sampleBuffer, source: .camera)

        let currentSource = await engine.currentSource
        let pendingSource = await engine.pendingSource
        #expect(currentSource == .screen)
        #expect(pendingSource == .camera)
        #expect(coordinator.startTimeNeedsRecalibration == true)

        _ = await engine.stopRecording()
    }

    @Test("Pending screen frames still complete camera to screen switch")
    func pendingScreenFramesStillCompleteCameraToScreenSwitch() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .camera)

        await configureSwitchState(
            engine,
            current: .camera,
            pending: .screen,
            needsRecalibration: true
        )

        let sampleBuffer = try makeVideoSampleBuffer(
            presentationTime: CMTime(value: 900, timescale: 600)
        )

        await engine.processSample(sampleBuffer, source: .screen)

        let currentSource = await engine.currentSource
        let pendingSource = await engine.pendingSource
        #expect(currentSource == .screen)
        #expect(pendingSource == nil)

        _ = await engine.stopRecording()
    }

    @Test("Screen to camera handoff uses latest written mic audio time")
    func screenToCameraHandoffUsesLatestWrittenMicAudioTime() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .screen)

        let writer = await makeActiveVideoWriterMock()
        await configureWriterState(engine, writer: writer, current: .camera)

        let coordinator = await engine.timeCoordinator
        let firstVideo = coordinator.processSampleTime(CMTime(seconds: 10, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(firstVideo.presentationTime)
        let secondVideo = coordinator.processSampleTime(CMTime(seconds: 11, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(secondVideo.presentationTime)
        coordinator.beginSourceSwitchRecalibration()

        let audioSample = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 11.8, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(audioSample)

        let cameraSample = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 12.0, preferredTimescale: 600)
        )
        await engine.processSample(cameraSample, source: .camera)

        #expect(await micWriteCallCount(writer) == 1)
        #expect(await videoWriteCallCount(writer) == 1)
        if let writtenTime = await lastWrittenVideoTime(writer) {
            #expect(abs(writtenTime - 11.9) < 0.001)
        } else {
            Issue.record("Expected the first post-switch camera frame to be written")
        }
        #expect(coordinator.startTimeNeedsRecalibration == false)

        _ = await engine.stopRecording()
    }

    @Test("Dropped first post-switch camera frame keeps recalibration armed")
    func droppedFirstPostSwitchCameraFrameKeepsRecalibrationArmed() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .screen)

        let writer = await makeActiveVideoWriterMock()
        let videoWriteAttempts = AttemptCounter()
        await makeFirstVideoWriteFail(writer, attempts: videoWriteAttempts)

        await configureWriterState(engine, writer: writer, current: .camera)

        let coordinator = await engine.timeCoordinator
        let firstVideo = coordinator.processSampleTime(CMTime(seconds: 10, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(firstVideo.presentationTime)
        let secondVideo = coordinator.processSampleTime(CMTime(seconds: 11, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(secondVideo.presentationTime)
        coordinator.beginSourceSwitchRecalibration()

        let droppedCameraSample = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 12.0, preferredTimescale: 600)
        )
        await engine.processSample(droppedCameraSample, source: .camera)
        #expect(coordinator.startTimeNeedsRecalibration == true)

        let audioSample = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 12.4, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(audioSample)

        let nextCameraSample = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 12.6, preferredTimescale: 600)
        )
        await engine.processSample(nextCameraSample, source: .camera)

        #expect(await videoWriteCallCount(writer) == 2)
        if let writtenTime = await lastWrittenVideoTime(writer) {
            #expect(abs(writtenTime - 12.5) < 0.001)
        } else {
            Issue.record("Expected the second post-switch camera frame to be written")
        }
        #expect(coordinator.startTimeNeedsRecalibration == false)

        _ = await engine.stopRecording()
    }

    @Test("Large video-only recalibration does not push microphone audio backwards")
    func largeVideoOnlyRecalibrationDoesNotPushMicrophoneAudioBackwards() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .screen)

        let writer = await makeActiveVideoWriterMock()
        let micPTSRecorder = MonotonicPTSRecorder()
        await configureWriterState(engine, writer: writer, current: .camera)
        await installMicMonotonicHandler(writer, recorder: micPTSRecorder)

        let coordinator = await engine.timeCoordinator
        let firstVideo = coordinator.processSampleTime(CMTime(seconds: 4679.9, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(firstVideo.presentationTime)
        let secondVideo = coordinator.processSampleTime(CMTime(seconds: 4680.0, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(secondVideo.presentationTime)

        let micBeforeSwitch = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 4680.34, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(micBeforeSwitch)
        #expect(await micWriteCallCount(writer) == 1)

        coordinator.beginSourceSwitchRecalibration()

        let postSwitchVideo = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 4704.83, preferredTimescale: 600)
        )
        await engine.processSample(postSwitchVideo, source: .camera)

        #expect(coordinator.timeOffset.seconds > 20.0)

        let micAfterSwitch = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 4680.50, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(micAfterSwitch)

        #expect(await micWriteCallCount(writer) == 2)
        if let writtenPTS = await lastWrittenMicTime(writer) {
            #expect(abs(writtenPTS - 4680.50) < 0.001)
        } else {
            Issue.record("Expected a post-switch microphone sample to be written")
        }
        #expect(micPTSRecorder.lastAccepted != nil)
        if let lastAcceptedMicPTS = micPTSRecorder.lastAccepted {
            #expect(abs(lastAcceptedMicPTS - 4680.50) < 0.001)
        }

        _ = await engine.stopRecording()
    }

    @Test("Repeated long-session source switches keep microphone monotonic and video contiguous")
    func repeatedLongSessionSourceSwitchesKeepTracksAligned() async throws {
        let engine = sut
        await engine.startRecording(initialSource: .screen)

        let writer = await makeActiveVideoWriterMock()
        let micPTSRecorder = MonotonicPTSRecorder()
        await configureWriterState(engine, writer: writer, current: .screen)
        await installMicMonotonicHandler(writer, recorder: micPTSRecorder)

        let coordinator = await engine.timeCoordinator

        let openingVideo = coordinator.processSampleTime(CMTime(seconds: 1799.90, preferredTimescale: 600))
        coordinator.recordWrittenPresentationTime(openingVideo.presentationTime)
        let latestPreSwitchVideo = coordinator.processSampleTime(
            CMTime(seconds: 1800.00, preferredTimescale: 600)
        )
        coordinator.recordWrittenPresentationTime(latestPreSwitchVideo.presentationTime)

        let micBeforeFirstSwitch = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 1800.35, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(micBeforeFirstSwitch)
        #expect(await micWriteCallCount(writer) == 1)

        coordinator.beginSourceSwitchRecalibration()
        await configureWriterState(engine, writer: writer, current: .camera)
        let firstPostSwitchCamera = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 1826.20, preferredTimescale: 600)
        )
        await engine.processSample(firstPostSwitchCamera, source: .camera)

        if let firstSwitchVideoPTS = await lastWrittenVideoTime(writer) {
            #expect(abs(firstSwitchVideoPTS - 1800.45) < 0.001)
        } else {
            Issue.record("Expected first post-switch camera frame to be written")
        }

        let micAfterFirstSwitch = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 1800.62, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(micAfterFirstSwitch)

        coordinator.beginSourceSwitchRecalibration()
        await configureWriterState(engine, writer: writer, current: .screen)
        let firstPostSwitchScreen = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 1854.80, preferredTimescale: 600)
        )
        await engine.processSample(firstPostSwitchScreen, source: .screen)

        if let secondSwitchVideoPTS = await lastWrittenVideoTime(writer) {
            #expect(abs(secondSwitchVideoPTS - 1800.72) < 0.001)
        } else {
            Issue.record("Expected first post-switch screen frame to be written")
        }

        let micAfterSecondSwitch = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 1800.88, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(micAfterSecondSwitch)

        coordinator.beginSourceSwitchRecalibration()
        await configureWriterState(engine, writer: writer, current: .camera)
        let secondPostSwitchCamera = try makeVideoSampleBuffer(
            presentationTime: CMTime(seconds: 1889.33, preferredTimescale: 600)
        )
        await engine.processSample(secondPostSwitchCamera, source: .camera)

        if let thirdSwitchVideoPTS = await lastWrittenVideoTime(writer) {
            #expect(abs(thirdSwitchVideoPTS - 1800.98) < 0.001)
        } else {
            Issue.record("Expected second post-switch camera frame to be written")
        }

        let micAfterThirdSwitch = try makeAudioSampleBuffer(
            presentationTime: CMTime(seconds: 1801.05, preferredTimescale: 48_000)
        )
        await engine.processAudioSample(micAfterThirdSwitch)

        #expect(await micWriteCallCount(writer) == 4)
        if let lastAcceptedMicPTS = micPTSRecorder.lastAccepted {
            #expect(abs(lastAcceptedMicPTS - 1801.05) < 0.001)
        } else {
            Issue.record("Expected monotonic microphone timestamps to be recorded across switches")
        }
        #expect(coordinator.startTimeNeedsRecalibration == false)

        _ = await engine.stopRecording()
    }
}

private final class ScreenRecorderCallCountingMock: ScreenRecorder {
    private(set) var startCallCount = 0

    override func start(outputURL: URL? = nil) async throws {
        startCallCount += 1
    }

    override func stop() async {}

    override func teardown() {}
}

private final class DelayedStartAudioService: AudioService {
    private let startDelayNanoseconds: UInt64?

    init(permissionManager: PermissionManager, startDelayNanoseconds: UInt64?) {
        self.startDelayNanoseconds = startDelayNanoseconds
        super.init(permissionManager: permissionManager)
    }

    override func start() {
        guard let startDelayNanoseconds else { return }

        Task { @MainActor in
            if startDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: startDelayNanoseconds)
            }
            self.isRunning = true
        }
    }

    override func stop() {
        isRunning = false
    }

    override func checkPermission() {}

    override func requestPermission() {}
}

@RecordingActor
private func setStopping(_ engine: RecordingEngine, _ value: Bool) {
    engine.isStopping = value
}

@RecordingActor
private func configureSwitchState(
    _ engine: RecordingEngine,
    current: RecordingSource,
    pending: RecordingSource,
    needsRecalibration: Bool
) {
    engine.currentSource = current
    engine.pendingSource = pending
    engine.isSwitching = true
    engine.timeCoordinator.startTimeNeedsRecalibration = needsRecalibration
}

@RecordingActor
private func configureWriterState(
    _ engine: RecordingEngine,
    writer: VideoWriterProtocol,
    current: RecordingSource,
    pending: RecordingSource? = nil,
    isSwitching: Bool = false
) {
    engine.videoWriter = writer
    engine.currentSource = current
    engine.pendingSource = pending
    engine.isSwitching = isSwitching
    engine.timeCoordinator.driftTracker = writer.driftTracker
}

private final class AttemptCounter: @unchecked Sendable {
    var value = 0
}

@RecordingActor
private func makeActiveVideoWriterMock() -> VideoWriterProtocolMock {
    let writer = VideoWriterProtocolMock()
    writer.isWriting = true
    writer.isReadyForData = true
    writer.driftTracker = DriftTracker()
    return writer
}

@RecordingActor
private func makeFirstVideoWriteFail(
    _ writer: VideoWriterProtocolMock,
    attempts: AttemptCounter
) {
    writer.writeVideoHandler = { _, _, _ in
        attempts.value += 1
        return attempts.value > 1
    }
}

@RecordingActor
private func micWriteCallCount(_ writer: VideoWriterProtocolMock) -> Int {
    writer.writeMicAudioCallCount
}

@RecordingActor
private func installMicMonotonicHandler(
    _ writer: VideoWriterProtocolMock,
    recorder: MonotonicPTSRecorder
) {
    writer.writeMicAudioHandler = { sampleBuffer in
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        return recorder.record(pts)
    }
}

@RecordingActor
private func videoWriteCallCount(_ writer: VideoWriterProtocolMock) -> Int {
    writer.writeVideoCallCount
}

@RecordingActor
private func lastWrittenVideoTime(_ writer: VideoWriterProtocolMock) -> Double? {
    writer.writeVideoArgValues.last?.presentationTime.seconds
}

@RecordingActor
private func lastWrittenMicTime(_ writer: VideoWriterProtocolMock) -> Double? {
    writer.writeMicAudioArgValues.last.map { CMSampleBufferGetPresentationTimeStamp($0).seconds }
}

private final class MonotonicPTSRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedPTS: [Double] = []

    func record(_ pts: Double) -> Bool {
        lock.withLock {
            if let last = acceptedPTS.last, pts <= last {
                return false
            }
            acceptedPTS.append(pts)
            return true
        }
    }

    var lastAccepted: Double? {
        lock.withLock { acceptedPTS.last }
    }
}

private func makeVideoSampleBuffer(presentationTime: CMTime) throws -> CMSampleBuffer {
    let attributes: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]

    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        4,
        4,
        kCVPixelFormatType_32BGRA,
        attributes as CFDictionary,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "RecordingEngineTests", code: Int(pixelStatus))
    }

    var formatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else {
        throw NSError(domain: "RecordingEngineTests", code: Int(formatStatus))
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: presentationTime
    )

    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
        throw NSError(domain: "RecordingEngineTests", code: Int(sampleStatus))
    }

    return sampleBuffer
}

private func makeAudioSampleBuffer(presentationTime: CMTime) throws -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(
        mSampleRate: 48_000,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2,
        mChannelsPerFrame: 1,
        mBitsPerChannel: 16,
        mReserved: 0
    )

    var formatDescription: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else {
        throw NSError(domain: "RecordingEngineTests", code: Int(formatStatus))
    }

    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: 2,
        blockAllocator: nil,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: 2,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
        throw NSError(domain: "RecordingEngineTests", code: Int(blockStatus))
    }

    var silence = [UInt8](repeating: 0, count: 2)
    let replaceStatus = CMBlockBufferReplaceDataBytes(
        with: &silence,
        blockBuffer: blockBuffer,
        offsetIntoDestination: 0,
        dataLength: silence.count
    )
    guard replaceStatus == kCMBlockBufferNoErr else {
        throw NSError(domain: "RecordingEngineTests", code: Int(replaceStatus))
    }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 48_000),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )
    var sampleSize = 2
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        formatDescription: formatDescription,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &sampleSize,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
        throw NSError(domain: "RecordingEngineTests", code: Int(sampleStatus))
    }

    return sampleBuffer
}
