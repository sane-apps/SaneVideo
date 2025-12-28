//
//  AppConstants.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreGraphics
import Foundation

enum AppConstants {
    // MARK: - Timeline

    static let timelineHeight: CGFloat = 120 // Optimized for screen real estate (was 200)
    static let pixelsPerSecond: CGFloat = 50.0

    // MARK: - UI

    static let defaultWindowWidth: CGFloat = 1400
    static let defaultWindowHeight: CGFloat = 900

    // MARK: - Timing (Nanoseconds)

    enum Timing {
        /// Small delay for UI sync (50ms)
        static let uiSync: UInt64 = 50_000_000

        /// Standard async delay (100ms)
        static let standard: UInt64 = 100_000_000

        /// Window animation completion delay (150ms)
        static let windowAnimation: UInt64 = 150_000_000

        /// Camera stabilization delay (200ms)
        static let cameraStabilization: UInt64 = 200_000_000

        /// SwiftUI teardown delay (300ms)
        static let swiftUITeardown: UInt64 = 300_000_000

        /// Camera switch timeout (10s)
        static let cameraSwitchTimeout: UInt64 = 10_000_000_000

        /// Screen picker timeout (120s / 2 minutes - user interaction required)
        static let screenPickerTimeout: UInt64 = 120_000_000_000

        /// Filter staleness threshold (5 minutes)
        static let filterStalenessThreshold: TimeInterval = 300

        /// Source switch polling interval (100ms)
        static let switchPollingInterval: UInt64 = 100_000_000

        /// Max source switch polling attempts (50 = 5 seconds)
        static let maxSwitchPollingAttempts = 50
    }

    // MARK: - Magic Features Configuration

    /// Configuration for AI/ML "magic" features
    enum MagicFeatures {

        // MARK: Vision Thresholds

        /// Minimum confidence for face detection (0.0-1.0)
        static let faceDetectionConfidence: Float = 0.5

        /// Minimum confidence for body pose joints (0.0-1.0)
        static let bodyPoseConfidence: Float = 0.3

        /// Minimum confidence for hand pose detection (0.0-1.0)
        static let handPoseConfidence: Float = 0.3

        /// Minimum confidence for text recognition (0.0-1.0)
        static let textRecognitionConfidence: Float = 0.5

        // MARK: Audio Thresholds

        /// RMS threshold for silence detection (0.0-1.0)
        static let silenceRMSThreshold: Float = 0.01

        /// Minimum silence duration to detect (seconds)
        static let minimumSilenceDuration: TimeInterval = 0.3

        /// Confidence threshold for filler word detection (0.0-1.0)
        static let fillerWordConfidence: Double = 0.6

        // MARK: Timeouts

        /// Voice isolation initialization timeout (seconds)
        static let voiceIsolationTimeout: TimeInterval = 5.0

        /// Video writer finish timeout (seconds)
        static let videoWriterFinishTimeout: TimeInterval = 30.0

        /// Export engine finish timeout (seconds)
        static let exportFinishTimeout: TimeInterval = 60.0

        /// Transcription segment timeout (seconds)
        static let transcriptionTimeout: TimeInterval = 30.0

        // MARK: Processing Limits

        /// Maximum audio file size for processing (bytes) - 500MB
        static let maxAudioFileSize: Int = 500 * 1024 * 1024

        /// Maximum video duration for real-time processing (seconds)
        static let maxRealtimeProcessingDuration: TimeInterval = 3600.0

        /// Frame skip interval for vision processing (process every Nth frame)
        static let visionFrameSkipInterval: Int = 3

        // MARK: Auto-Framing

        /// Padding around detected faces for auto-framing (0.0-1.0 of face size)
        static let autoFramePadding: CGFloat = 0.3

        /// Smoothing factor for face tracking (0.0=no smoothing, 1.0=max smoothing)
        static let faceTrackingSmoothingFactor: CGFloat = 0.7

        /// Default target aspect ratio for auto-framing
        static let autoFrameAspectRatio: CGFloat = 16.0 / 9.0
    }
}
