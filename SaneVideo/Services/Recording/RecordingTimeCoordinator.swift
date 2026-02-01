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
        set { lock.withLock { _timeOffset = newValue } }
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
            _startTimeNeedsRecalibration = false
            _lastRecordedTime = .zero
            _pauseTime = .zero
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
        }
    }
    
    // MARK: - Processing
    
    struct ProcessingResult {
        let presentationTime: CMTime
        let shouldWrite: Bool
        let isFirstSample: Bool
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
                isFirstSample = true
                AppLogger.recording.info("Recording started. First sample time: \(self._startTime.seconds)")
            } else if _startTimeNeedsRecalibration {
                // Recalibrate (inline to stay within lock)
                let gap = CMTime(value: 100, timescale: 1000) // 100ms gap
                let lastAbsoluteTime = CMTimeAdd(_startTime, _lastRecordedTime)
                let targetNewTime = CMTimeAdd(lastAbsoluteTime, gap)
                let newTimeOffset = CMTimeSubtract(samplePresentationTime, targetNewTime)
                _timeOffset = newTimeOffset
                _startTimeNeedsRecalibration = false
                AppLogger.recording.info("Time base recalibrated. Safe gap added: 100ms. New offset: \(self._timeOffset.seconds)s, continuing from: \(self._lastRecordedTime.seconds)s")
            }

            var presentationTime = samplePresentationTime
            if _timeOffset != .zero {
                presentationTime = CMTimeSubtract(presentationTime, _timeOffset)
            }

            // Apply drift correction if tracker is active
            if let driftTracker {
                let correction = driftTracker.calculateCorrection()
                if abs(correction) > 0.001 {
                    let correctionTime = CMTime(seconds: correction, preferredTimescale: presentationTime.timescale)
                    presentationTime = CMTimeSubtract(presentationTime, correctionTime)
                }
            }

            // Track last recorded time
            _lastRecordedTime = CMTimeSubtract(presentationTime, _startTime)

            return ProcessingResult(
                presentationTime: presentationTime,
                shouldWrite: true, // Logic flow handled by caller checking writer state
                isFirstSample: isFirstSample
            )
        }
    }
    
    /// Adjust sample buffer timing based on current offset
    func adjustBufferTime(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        // Capture offset atomically once to avoid multiple lock acquisitions
        let currentOffset = timeOffset
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
