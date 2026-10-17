import CoreGraphics
import Foundation

enum AppConstants {
    // MARK: - Timeline

    static let timelineHeight: CGFloat = 120
    static let pixelsPerSecond: CGFloat = 50.0

    // MARK: - UI

    static let defaultWindowWidth: CGFloat = 1400
    static let defaultWindowHeight: CGFloat = 900

    // MARK: - Timing (Nanoseconds)

    enum Timing {
        static let uiSync: UInt64 = 50_000_000

        static let standard: UInt64 = 100_000_000

        static let windowAnimation: UInt64 = 150_000_000

        static let cameraStabilization: UInt64 = 200_000_000

        static let swiftUITeardown: UInt64 = 300_000_000

        static let cameraSwitchTimeout: UInt64 = 10_000_000_000

        /// Long because the user has to choose a screen.
        static let screenPickerTimeout: UInt64 = 120_000_000_000

        static let filterStalenessThreshold: TimeInterval = 300

        static let switchPollingInterval: UInt64 = 100_000_000

        /// Max source switch polling attempts (50 = 5 seconds)
        static let maxSwitchPollingAttempts = 50
    }

    // MARK: - Magic Features Configuration

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

        static let minimumSilenceDuration: TimeInterval = 0.3

        /// Confidence threshold for filler word detection (0.0-1.0)
        static let fillerWordConfidence: Double = 0.6

        // MARK: Timeouts

        static let voiceIsolationTimeout: TimeInterval = 5.0

        static let videoWriterFinishTimeout: TimeInterval = 30.0

        static let exportFinishTimeout: TimeInterval = 60.0

        static let transcriptionTimeout: TimeInterval = 30.0

        // MARK: Processing Limits

        static let maxAudioFileSize: Int = 500 * 1024 * 1024

        static func isFileSizeValid(_ url: URL) -> Bool {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else {
                return true // Allow if can't determine size
            }
            return size <= maxAudioFileSize
        }

        /// Returns the file size in bytes, or nil if unavailable
        static func fileSize(_ url: URL) -> Int? {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else {
                return nil
            }
            return size
        }

        static let maxRealtimeProcessingDuration: TimeInterval = 3600.0

        /// Frame skip interval for vision processing (process every Nth frame)
        static let visionFrameSkipInterval: Int = 3

        /// Vision processing sample interval in seconds (controls FPS of analysis)
        static let visionSampleInterval: TimeInterval = 0.5

        /// Number of frames between Task.yield() calls for cooperative multitasking
        static let visionYieldInterval: Int = 10

        // MARK: Auto-Framing

        /// Padding around detected faces for auto-framing (0.0-1.0 of face size)
        static let autoFramePadding: CGFloat = 0.3

        /// Smoothing factor for face tracking (0.0=no smoothing, 1.0=max smoothing)
        static let faceTrackingSmoothingFactor: CGFloat = 0.7

        static let autoFrameAspectRatio: CGFloat = 16.0 / 9.0
    }
}
