//
//  AudioService.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

@preconcurrency import AVFoundation
import Accelerate
@preconcurrency import Combine

private struct SubjectBox<Output>: @unchecked Sendable {
  let subject = PassthroughSubject<Output, Never>()

  func send(_ value: Output) {
    subject.send(value)
  }
}

@MainActor
@Observable
class AudioService: NSObject, AudioServiceProtocol {
  // MARK: - State Properties

  var isRunning = false
  var permissionGranted = false
  var currentMicID: String?
  private(set) var availableMicrophones: [AVCaptureDevice] = []

  // MARK: - Subjects

  private nonisolated let sampleBufferSubjectBox = SubjectBox<CMSampleBuffer>()
  private nonisolated let audioLevelSubjectBox = SubjectBox<Float>()

  nonisolated var sampleBufferSubject: PassthroughSubject<CMSampleBuffer, Never> {
    sampleBufferSubjectBox.subject
  }

  nonisolated var audioLevelSubject: PassthroughSubject<Float, Never> {
    audioLevelSubjectBox.subject
  }

  // MARK: - Internal Properties

  private var session: AVCaptureSession?
  private let permissionManager: PermissionManager
  private var cancellables = Set<AnyCancellable>()
  private var hasDiscoveredMicrophones = false
  private var lastAudioLevelUpdateTime = ContinuousClock.Instant.now

  // MARK: - Initialization

  init(permissionManager: PermissionManager) {
    self.permissionManager = permissionManager
    super.init()
    Task { @MainActor in
      setupBindings()
    }
  }

  @MainActor
  private func setupBindings() {
    // Crash fix: Ensure main queue delivery for thread safety
    permissionManager.microphoneStatusPublisher
      .receive(on: DispatchQueue.main)
      .map { $0 == .granted }
      .sink { [weak self] granted in
        self?.permissionGranted = granted
      }
      .store(in: &cancellables)
  }

  // MARK: - Discovery

  /// Refresh the list of available microphones (call when user interacts with mic picker)
  func refreshMicrophones() {
    if TestEnvironment.isTesting {
      Task { @MainActor in
        self.availableMicrophones = []
        self.hasDiscoveredMicrophones = true
        AppLogger.audio.info("🧪 [TEST] Bypassing microphone discovery")
      }
      return
    }

    // Only query DiscoverySession when explicitly requested
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.microphone, .external],
      mediaType: .audio,
      position: .unspecified
    )
    let devices = discovery.devices

    Task { @MainActor in
      self.availableMicrophones = devices
      self.hasDiscoveredMicrophones = true
      AppLogger.audio.debug("Refreshed microphone list: \(devices.count) devices found")
    }
  }

  /// Ensure microphones are discovered (lazy initialization)
  func ensureMicrophonesDiscovered() {
    if !hasDiscoveredMicrophones {
      refreshMicrophones()
    }
  }

  // MARK: - Permission

  func checkPermission() {
    if TestEnvironment.suppressPermissionPrompts { return }

    Task { @MainActor in
      permissionManager.checkMicrophonePermission()
    }
  }

  func requestPermission() {
    if TestEnvironment.suppressPermissionPrompts { return }

    Task {
      _ = await permissionManager.requestMicrophonePermission()
    }
  }

  // MARK: - Session Control

  func start() {
    if TestEnvironment.isTesting {
      isRunning = true
      AppLogger.audio.info("🧪 [TEST] Bypassing real microphone start")
      return
    }

    Task {
      AppLogger.audio.info("start() called")

      permissionManager.checkMicrophonePermission()
      let isAuthorized = permissionManager.microphoneStatus == .granted
      AppLogger.audio.debug("Permission status authorized: \(isAuthorized)")

      guard isAuthorized else {
        if TestEnvironment.suppressPermissionPrompts {
          AppLogger.audio.info("Permissionless automation active; skipping microphone permission prompt")
          return
        }
        AppLogger.audio.warning("Microphone permission not granted, requesting...")
        let granted = await permissionManager.requestMicrophonePermission()
        if granted {
          AppLogger.audio.info("Permission granted, starting session...")
          self.start()
        } else {
          AppLogger.audio.error("Permission denied by user")
        }
        return
      }

      await self.internalStart()

      // Ensure we have the list for the UI
      self.refreshMicrophones()
    }
  }

  private func internalStart() async {
    if self.session == nil {
      AppLogger.audio.info("Setting up new session...")
      await self.setupSession()
    }

    guard let session = self.session else {
      AppLogger.audio.error("Failed to create session!")
      return
    }

    if !session.isRunning {
      AppLogger.audio.info("Starting session...")
      await Task.detached(priority: .userInitiated) {
        session.startRunning()
      }.value

      try? await Task.sleep(nanoseconds: 200_000_000)

      if session.isRunning {
        AppLogger.audio.info("Session is running")
        self.isRunning = true
      } else {
        AppLogger.audio.error("Session failed to start!")
        self.isRunning = false
      }
    }
  }

  func stop() {
    guard let session = self.session else { return }

    Task {
      if session.isRunning {
        await Task.detached(priority: .userInitiated) {
          session.stopRunning()
        }.value
        AppLogger.audio.info("Session stopped")
      }
      self.isRunning = false
    }
  }

  // MARK: - Setup

  private func setupSession(device: AVCaptureDevice? = nil) async {
    let session = AVCaptureSession()

    let lastMicID = UserDefaults.standard.string(forKey: "lastUsedMicID")
    var audioDevice = device

    // 1. Try to restore last used mic if no specific device requested
    if audioDevice == nil, let lastID = lastMicID {
      let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
      )
      if let mic = discovery.devices.first(where: { $0.uniqueID == lastID }) {
        audioDevice = mic
        AppLogger.audio.info("Restoring last used microphone: \(mic.localizedName)")
      }
    }

    // 2. Fallback to default
    if audioDevice == nil {
      audioDevice = AVCaptureDevice.default(for: .audio)
    }

    guard let mic = audioDevice else {
      AppLogger.audio.error("No audio device found")
      return
    }

    do {
      let input = try AVCaptureDeviceInput(device: mic)
      if session.canAddInput(input) {
        session.addInput(input)
        self.currentMicID = mic.uniqueID
      }
    } catch {
      AppLogger.audio.error("Failed to create audio input: \(error.localizedDescription)")
      return
    }

    let output = AVCaptureAudioDataOutput()
    output.setSampleBufferDelegate(self, queue: .global(qos: .userInteractive))

    if session.canAddOutput(output) {
      session.addOutput(output)
    }

    self.session = session
    AppLogger.audio.info("Session setup complete with mic: \(mic.localizedName)")
  }

  // MARK: - Microphone Switching

  func switchMicrophone(to device: AVCaptureDevice) {
    Task {
      guard let session = self.session else { return }

      session.beginConfiguration()

      // Remove current audio input
      for input in session.inputs {
        if let deviceInput = input as? AVCaptureDeviceInput,
          deviceInput.device.hasMediaType(.audio) {
          session.removeInput(deviceInput)
        }
      }

      // Add new input
      do {
        let newInput = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(newInput) {
          session.addInput(newInput)
          self.currentMicID = device.uniqueID
          UserDefaults.standard.set(device.uniqueID, forKey: "lastUsedMicID")
          AppLogger.audio.info("Switched to microphone: \(device.localizedName)")
        }
      } catch {
        AppLogger.audio.error("Failed to switch microphone: \(error)")
      }

      session.commitConfiguration()
    }
  }

  // MARK: - Audio Level Calculation

  private func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
      let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
    else { return }

    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
    let isFloat = (asbd?.mFormatFlags ?? 0) & kAudioFormatFlagIsFloat != 0

    var length = 0
    var dataPointer: UnsafeMutablePointer<Int8>?

    guard
      CMBlockBufferGetDataPointer(
        blockBuffer,
        atOffset: 0,
        lengthAtOffsetOut: nil,
        totalLengthOut: &length,
        dataPointerOut: &dataPointer
      ) == kCMBlockBufferNoErr,
      let data = dataPointer
    else { return }

    var sum: Float = 0
    var sampleCount = 0

    if isFloat {
      // Float32 (Standard for macOS audio)
      let samples = length / 4
      let ptr = data.withMemoryRebound(to: Float.self, capacity: samples) { $0 }

      // RMS over all samples
      for index in 0..<samples {
        let sample = ptr[index]
        sum += sample * sample
      }
      sampleCount = samples
    } else {
      // Int16 (Fallback)
      let samples = length / 2
      let ptr = data.withMemoryRebound(to: Int16.self, capacity: samples) { $0 }

      for index in 0..<samples {
        let sample = Float(ptr[index]) / Float(Int16.max)
        sum += sample * sample
      }
      sampleCount = samples
    }

    guard sampleCount > 0 else { return }

    let rms = sqrt(sum / Float(sampleCount))

    // Safety check for NaN or Infinity
    guard !rms.isNaN && !rms.isInfinite else {
      audioLevelSubjectBox.send(0)
      return
    }

    let decibels = 20 * log10(rms)

    // Normalize -60dB to 0dB range to 0.0-1.0
    let normalized = max(0.0, min(1.0, (decibels + 60) / 60))

    audioLevelSubjectBox.send(normalized)
  }
}

// MARK: - Delegate

extension AudioService: AVCaptureAudioDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection
  ) {
    sampleBufferSubjectBox.send(sampleBuffer)

    // PERFORMANCE: Throttle audio levels to ~15fps for UI
    let now = ContinuousClock().now

    // We can't access lastAudioLevelUpdateTime directly as it's @MainActor
    // But we can check it via a task or just pass it to calculateAudioLevel which is nonisolated

    Task { @MainActor in
      if now - lastAudioLevelUpdateTime >= .milliseconds(66) {
        lastAudioLevelUpdateTime = now
        calculateAudioLevel(from: sampleBuffer)
      }
    }
  }
}
