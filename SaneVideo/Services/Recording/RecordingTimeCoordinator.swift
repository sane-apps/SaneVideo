//
//  RecordingTimeCoordinator.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreMedia
import Foundation
import OSLog

/// Manages recording time, pauses, and source switch recalibration
/// Thread-safe via NSLock synchronization
class RecordingTimeCoordinator: @unchecked Sendable {

    // MARK: - Thread Safety

    private let lock = NSLock()

    // MARK: - State (all access must be synchronized via lock)

    private var _startTime: CMTime = .zero
    private var _pauseTime: CMTime = .zero
    private var _timeOffset: CMTime = .zero
    private var _microphoneTimeOffset: CMTime = .zero
    private var _pendingTimeOffset: CMTime?
    private var _startTimeNeedsRecalibration = false
    private var _lastRecordedTime: CMTime = .zero

    // MARK: - Drift Correction

    /// Optional drift tracker for A/V sync correction
    var driftTracker: DriftTracker?

    // Thread-safe accessors
    var startTime: CMTime {
        get { lock.withLock { _startTime } }
        set { lock.withLock { _startTime = newValue } }
    }

    var pauseTime: CMTime {
        get { lock.withLock { _pauseTime } }
        set { lock.withLock { _pauseTime = newValue } }
    }

    var timeOffset: CMTime {
        get { lock.withLock { _timeOffset } }
        set {
            lock.withLock {
                _timeOffset = newValue
                _microphoneTimeOffset = newValue
            }
        }
    }

    var startTimeNeedsRecalibration: Bool {
        get { lock.withLock { _startTimeNeedsRecalibration } }
        set { lock.withLock { _startTimeNeedsRecalibration = newValue } }
    }

    var lastRecordedTime: CMTime {
        get { lock.withLock { _lastRecordedTime } }
        set { lock.withLock { _lastRecordedTime = newValue } }
    }
    
    // MARK: - Lifecycle

    func reset() {
        lock.withLock {
            _startTime = .zero
            _timeOffset = .zero
            _microphoneTimeOffset = .zero
            _pendingTimeOffset = nil
            _startTimeNeedsRecalibration = false
            _lastRecordedTime = .zero
            _pauseTime = .zero
            driftTracker = nil
        }
    }

    func beginSourceSwitchRecalibration() {
        lock.withLock {
            _startTimeNeedsRecalibration = true
            _pendingTimeOffset = nil
            driftTracker?.reset()
        }
    }

    func commitPendingRecalibrationIfNeeded(applyToMicrophone: Bool = false) {
        lock.withLock {
            guard let pendingTimeOffset = _pendingTimeOffset else { return }
            _timeOffset = pendingTimeOffset
            if applyToMicrophone {
                _microphoneTimeOffset = pendingTimeOffset
            }
            _pendingTimeOffset = nil
            _startTimeNeedsRecalibration = false
        }
    }

    func recordWrittenPresentationTime(_ presentationTime: CMTime) {
        lock.withLock {
            guard _startTime != .zero else { return }
            guard presentationTime >= _startTime else { return }

            let relativeTime = CMTimeSubtract(presentationTime, _startTime)
            if relativeTime > _lastRecordedTime {
                _lastRecordedTime = relativeTime
            }
        }
    }

    // MARK: - Pause/Resume

    func pause() {
        lock.withLock {
            _pauseTime = CMClockGetTime(CMClockGetHostTimeClock())
        }
    }

    func resume() {
        lock.withLock {
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let pauseDuration = CMTimeSubtract(now, _pauseTime)
            _timeOffset = CMTimeAdd(_timeOffset, pauseDuration)
            _microphoneTimeOffset = CMTimeAdd(_microphoneTimeOffset, pauseDuration)
        }
    }
    
    // MARK: - Processing
    
    struct ProcessingResult {
        let presentationTime: CMTime
        let shouldWrite: Bool
        let isFirstSample: Bool
        let usedPendingRecalibration: Bool
    }
    
    /// Process a sample buffer timestamp and return adjusted time and write decision
    func processSampleTime(_ samplePresentationTime: CMTime) -> ProcessingResult {
        lock.withLock {
            var isFirstSample = false

            // Handle first sample OR source switch recalibration
            if _startTime == .zero {
                // First sample ever - set the baseline
                _startTime = samplePresentationTime
                _startTimeNeedsRecalibration = false
                _pendingTimeOffset = nil
                isFirstSample = true
                AppLogger.recording.info("Recording started. First sample time: \(self._startTime.seconds)")
            }

            var offsetToApply = _timeOffset
            var usedPendingRecalibration = false

            if _startTimeNeedsRecalibration {
                // Recalibrate (inline to stay within lock)
                let gap = CMTime(value: 100, timescale: 1000) // 100ms gap
                let lastAbsoluteTime = CMTimeAdd(_startTime, _lastRecordedTime)
                let targetNewTime = CMTimeAdd(lastAbsoluteTime, gap)
                let newTimeOffset = CMTimeSubtract(samplePresentationTime, targetNewTime)
                _pendingTimeOffset = newTimeOffset
                offsetToApply = newTimeOffset
                usedPendingRecalibration = true
                AppLogger.recording.info("Time base recalibration candidate prepared. Safe gap added: 100ms. Pending offset: \(newTimeOffset.seconds)s, continuing from: \(self._lastRecordedTime.seconds)s")
            }

            var presentationTime = samplePresentationTime
            if offsetToApply != .zero {
                presentationTime = CMTimeSubtract(presentationTime, offsetToApply)
            }

            // Apply drift correction if tracker is active
            if let driftTracker {
                let correction = driftTracker.calculateCorrection()
                if abs(correction) > 0.001 {
                    let correctionTime = CMTime(seconds: correction, preferredTimescale: presentationTime.timescale)
                    presentationTime = CMTimeSubtract(presentationTime, correctionTime)
                }
            }

            return ProcessingResult(
                presentationTime: presentationTime,
                shouldWrite: true, // Logic flow handled by caller checking writer state
                isFirstSample: isFirstSample,
                usedPendingRecalibration: usedPendingRecalibration
            )
        }
    }
    
    /// Adjust sample buffer timing based on current offset
    func adjustBufferTime(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        let currentOffset = lock.withLock { _timeOffset }
        return adjustBufferTime(sample, currentOffset: currentOffset)
    }

    /// Adjust microphone timing without applying video-only source-switch recalibration.
    func adjustMicrophoneBufferTime(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        let currentOffset = lock.withLock { _microphoneTimeOffset }
        return adjustBufferTime(sample, currentOffset: currentOffset)
    }

    private func adjustBufferTime(_ sample: CMSampleBuffer, currentOffset: CMTime) -> CMSampleBuffer {
        guard currentOffset != .zero else { return sample }

        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)

        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: Int(count))
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &info, entriesNeededOut: nil)

        for index in 0 ..< Int(count) {
            info[index].decodeTimeStamp = CMTimeSubtract(info[index].decodeTimeStamp, currentOffset)
            info[index].presentationTimeStamp = CMTimeSubtract(info[index].presentationTimeStamp, currentOffset)
        }

        var newSample: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: count,
            sampleTimingArray: &info,
            sampleBufferOut: &newSample
        )

        return newSample ?? sample
    }
}
