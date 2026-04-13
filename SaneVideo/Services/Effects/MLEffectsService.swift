//
//  MLEffectsService.swift
//  SaneVideo
//
//  VideoToolbox ML-powered video effects using VTFrameProcessor
//  Provides: Super Resolution, Temporal Noise Filter, Frame Rate Conversion
//

import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// ML effect types available
enum MLEffectType: String, CaseIterable, Identifiable, Sendable {
    case superResolution = "Super Resolution"
    case denoise = "Noise Reduction"
    case frameInterpolation = "Frame Interpolation"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .superResolution: return "arrow.up.left.and.arrow.down.right"
        case .denoise: return "sparkles"
        case .frameInterpolation: return "film.stack"
        }
    }

    var description: String {
        switch self {
        case .superResolution:
            return "ML upscaling to higher resolution"
        case .denoise:
            return "Temporal noise reduction for cleaner video"
        case .frameInterpolation:
            return "Smooth motion with interpolated frames"
        }
    }

    /// Whether this effect is suitable for real-time preview
    var supportsRealTimePreview: Bool {
        switch self {
        case .denoise: return true
        case .superResolution, .frameInterpolation: return false
        }
    }
}

/// Configuration for ML effects
struct MLEffectConfiguration: Sendable {
    var type: MLEffectType
    var intensity: Float // 0.0 - 1.0
    var isEnabled: Bool

    init(type: MLEffectType, intensity: Float = 1.0, isEnabled: Bool = true) {
        self.type = type
        self.intensity = min(max(intensity, 0), 1)
        self.isEnabled = isEnabled
    }
}

enum SuperResolutionModelStatus: Sendable {
    case ready
    case downloading
    case downloadRequired
    case unsupported
}

/// Actor for ML-powered video effects using VideoToolbox
/// NOTE: VTFrameProcessor requires macOS 15.4+, some configs require macOS 26+
actor MLEffectsService {
    // MARK: - Properties
    // Use Any? to avoid compile-time availability issues with VTFrameProcessor (macOS 15.4+)
    // and configuration types (macOS 26.0+)

    private var superResProcessor: Any?
    private var denoiseProcessor: Any?
    private var frameRateProcessor: Any?

    private var superResConfig: Any?
    private var denoiseConfig: Any?
    private var frameRateConfig: Any?

    // Store previous frames for super resolution
    private var previousSourceFrame: Any?
    private var previousOutputFrame: Any?

    private var isInitialized = false

    // MARK: - Availability Checks

    /// Check if super resolution is supported (requires macOS 26+)
    nonisolated static var isSuperResolutionSupported: Bool {
#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            return VTSuperResolutionScalerConfiguration.isSupported
        }
#endif
        return false
    }

    /// Check if temporal noise filter is supported
    nonisolated static var isDenoiseSupported: Bool {
        if #available(macOS 26.0, *) {
            return VTTemporalNoiseFilterConfiguration.isSupported
        }
        return false
    }

    /// Check if frame rate conversion is supported
    nonisolated static var isFrameRateConversionSupported: Bool {
        if #available(macOS 15.4, *) {
            return VTFrameRateConversionConfiguration.isSupported
        }
        return false
    }

    // MARK: - Model Status (Super Resolution)

    /// Get super resolution model status from a temporary config instance
    nonisolated static var superResolutionModelStatus: SuperResolutionModelStatus {
#if swift(>=6.2)
        if #available(macOS 26.0, *) {
            guard let config = VTSuperResolutionScalerConfiguration(
                frameWidth: 1920,
                frameHeight: 1080,
                scaleFactor: 2,
                inputType: .video,
                usePrecomputedFlow: false,
                qualityPrioritization: .normal,
                revision: .revision1
            ) else {
                return .downloadRequired
            }

            switch config.configurationModelStatus {
            case .ready:
                return .ready
            case .downloading:
                return .downloading
            case .downloadRequired:
                return .downloadRequired
            @unknown default:
                return .unsupported
            }
        }
#endif
        return .unsupported
    }

    /// Download ML models required for super resolution
    @available(macOS 26.0, *)
    func downloadSuperResolutionModel() async throws {
#if swift(>=6.2)
        // Create a config instance to trigger download
        guard let config = VTSuperResolutionScalerConfiguration(
            frameWidth: 1920,
            frameHeight: 1080,
            scaleFactor: 2,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: .revision1
        ) else {
            throw MLEffectsError.configurationFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            config.downloadConfigurationModel { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
#else
        throw MLEffectsError.unsupported
#endif
    }

    // MARK: - Session Management

    /// Start a super resolution session
    @available(macOS 26.0, *)
    func startSuperResolutionSession(
        frameWidth: Int,
        frameHeight: Int,
        scaleFactor: Int = 2
    ) throws {
#if swift(>=6.2)
        guard let config = VTSuperResolutionScalerConfiguration(
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            scaleFactor: scaleFactor,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: .revision1
        ) else {
            throw MLEffectsError.configurationFailed
        }

        guard config.configurationModelStatus == .ready else {
            throw MLEffectsError.modelNotReady
        }

        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)

        self.superResProcessor = processor
        self.superResConfig = config
        self.previousSourceFrame = nil
        self.previousOutputFrame = nil
        isInitialized = true
#else
        throw MLEffectsError.unsupported
#endif
    }

    /// Start a denoise session
    @available(macOS 26.0, *)
    func startDenoiseSession(
        frameWidth: Int,
        frameHeight: Int,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA
    ) throws {
        guard VTTemporalNoiseFilterConfiguration.isSupported else {
            throw MLEffectsError.unsupported
        }

        guard let config = VTTemporalNoiseFilterConfiguration(
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            sourcePixelFormat: pixelFormat
        ) else {
            throw MLEffectsError.configurationFailed
        }

        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)

        self.denoiseProcessor = processor
        self.denoiseConfig = config
        isInitialized = true
    }

    /// Start a frame rate conversion session
    @available(macOS 15.4, *)
    func startFrameRateSession(
        frameWidth: Int,
        frameHeight: Int,
        qualityPrioritization: VTFrameRateConversionConfiguration.QualityPrioritization = .quality
    ) throws {
        guard let config = VTFrameRateConversionConfiguration(
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            usePrecomputedFlow: false,
            qualityPrioritization: qualityPrioritization,
            revision: .revision1
        ) else {
            throw MLEffectsError.configurationFailed
        }

        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)

        self.frameRateProcessor = processor
        self.frameRateConfig = config
        isInitialized = true
    }

    /// End all active sessions
    func endAllSessions() {
        if #available(macOS 15.4, *) {
            if let processor = superResProcessor as? VTFrameProcessor {
                processor.endSession()
            }
            if let processor = denoiseProcessor as? VTFrameProcessor {
                processor.endSession()
            }
            if let processor = frameRateProcessor as? VTFrameProcessor {
                processor.endSession()
            }
        }
        superResProcessor = nil
        superResConfig = nil
        denoiseProcessor = nil
        denoiseConfig = nil
        frameRateProcessor = nil
        frameRateConfig = nil
        previousSourceFrame = nil
        previousOutputFrame = nil
        isInitialized = false
    }

    // MARK: - Processing

    /// Apply super resolution to a frame
    @available(macOS 26.0, *)
    func applySuperResolution(
        sourceBuffer: CVPixelBuffer,
        destinationBuffer: CVPixelBuffer,
        presentationTime: CMTime
    ) async throws {
#if swift(>=6.2)
        guard let processor = superResProcessor as? VTFrameProcessor else {
            throw MLEffectsError.sessionNotStarted
        }

        let sourceFrame = VTFrameProcessorFrame(
            buffer: sourceBuffer,
            presentationTimeStamp: presentationTime
        )
        let destinationFrame = VTFrameProcessorFrame(
            buffer: destinationBuffer,
            presentationTimeStamp: presentationTime
        )

        guard let sourceFrame, let destinationFrame else {
            throw MLEffectsError.configurationFailed
        }

        let parameters = VTSuperResolutionScalerParameters(
            sourceFrame: sourceFrame,
            previousFrame: previousSourceFrame as? VTFrameProcessorFrame,
            previousOutputFrame: previousOutputFrame as? VTFrameProcessorFrame,
            opticalFlow: nil,
            submissionMode: (previousSourceFrame as? VTFrameProcessorFrame) == nil ? .random : .sequential,
            destinationFrame: destinationFrame
        )

        guard let parameters else {
            throw MLEffectsError.configurationFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Store for next frame
        previousSourceFrame = sourceFrame
        previousOutputFrame = destinationFrame
#else
        throw MLEffectsError.unsupported
#endif
    }

    /// Apply temporal noise filter to a frame
    @available(macOS 26.0, *)
    func applyDenoise(
        sourceBuffer: CVPixelBuffer,
        previousFrames: [CVPixelBuffer],
        nextFrames: [CVPixelBuffer],
        destinationBuffer: CVPixelBuffer,
        filterStrength: Float = 0.5,
        presentationTime: CMTime
    ) async throws {
        guard let processor = denoiseProcessor as? VTFrameProcessor else {
            throw MLEffectsError.sessionNotStarted
        }

        guard let sourceFrame = VTFrameProcessorFrame(
            buffer: sourceBuffer,
            presentationTimeStamp: presentationTime
        ) else {
            throw MLEffectsError.configurationFailed
        }

        guard let destinationFrame = VTFrameProcessorFrame(
            buffer: destinationBuffer,
            presentationTimeStamp: presentationTime
        ) else {
            throw MLEffectsError.configurationFailed
        }

        let prevFrames = previousFrames.compactMap { buffer in
            VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: .zero)
        }
        let nextFramesArray = nextFrames.compactMap { buffer in
            VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: .zero)
        }

        guard let parameters = VTTemporalNoiseFilterParameters(
            sourceFrame: sourceFrame,
            nextFrames: nextFramesArray,
            previousFrames: prevFrames,
            destinationFrame: destinationFrame,
            filterStrength: filterStrength,
            hasDiscontinuity: false
        ) else {
            throw MLEffectsError.configurationFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Apply frame rate conversion (interpolate frames between source and next)
    @available(macOS 15.4, *)
    func applyFrameRateConversion(
        sourceBuffer: CVPixelBuffer,
        nextBuffer: CVPixelBuffer,
        destinationBuffers: [CVPixelBuffer],
        interpolationPhases: [Float],
        presentationTime: CMTime
    ) async throws {
        guard let processor = frameRateProcessor as? VTFrameProcessor else {
            throw MLEffectsError.sessionNotStarted
        }

        guard destinationBuffers.count == interpolationPhases.count else {
            throw MLEffectsError.configurationFailed
        }

        guard let sourceFrame = VTFrameProcessorFrame(
            buffer: sourceBuffer,
            presentationTimeStamp: presentationTime
        ) else {
            throw MLEffectsError.configurationFailed
        }

        guard let nextFrame = VTFrameProcessorFrame(
            buffer: nextBuffer,
            presentationTimeStamp: presentationTime
        ) else {
            throw MLEffectsError.configurationFailed
        }

        let destFrames = destinationBuffers.compactMap { buffer in
            VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: presentationTime)
        }

        guard destFrames.count == destinationBuffers.count else {
            throw MLEffectsError.configurationFailed
        }

        guard let parameters = VTFrameRateConversionParameters(
            sourceFrame: sourceFrame,
            nextFrame: nextFrame,
            opticalFlow: nil,
            interpolationPhase: interpolationPhases,
            submissionMode: .sequential,
            destinationFrames: destFrames
        ) else {
            throw MLEffectsError.configurationFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Errors

enum MLEffectsError: LocalizedError {
    case modelNotReady
    case unsupported
    case configurationFailed
    case sessionNotStarted
    case processingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "ML model not downloaded. Please download the model first."
        case .unsupported:
            return "This ML effect is not supported on this device."
        case .configurationFailed:
            return "Failed to configure the ML effect processor."
        case .sessionNotStarted:
            return "ML effect session not started. Call start*Session first."
        case .processingFailed(let error):
            return "ML processing failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Protocol

protocol MLEffectsServiceProtocol: Actor {
    static var isSuperResolutionSupported: Bool { get }
    static var isDenoiseSupported: Bool { get }
    static var isFrameRateConversionSupported: Bool { get }

    @available(macOS 26.0, *)
    func startSuperResolutionSession(frameWidth: Int, frameHeight: Int, scaleFactor: Int) throws

    @available(macOS 26.0, *)
    func startDenoiseSession(frameWidth: Int, frameHeight: Int, pixelFormat: OSType) throws

    @available(macOS 15.4, *)
    func startFrameRateSession(
        frameWidth: Int,
        frameHeight: Int,
        qualityPrioritization: VTFrameRateConversionConfiguration.QualityPrioritization
    ) throws

    func endAllSessions()
}

extension MLEffectsService: MLEffectsServiceProtocol {}
