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
class RecordingTimeCoordinator: @unchecked Sendable {
    
    // MARK: - State
    
    var startTime: CMTime = .zero
    var pauseTime: CMTime = .zero
    var timeOffset: CMTime = .zero
    
    // Source switch recalibration
    var startTimeNeedsRecalibration = false
    var lastRecordedTime: CMTime = .zero
    
    // MARK: - Lifecycle
    
    func reset() {
        startTime = .zero
        timeOffset = .zero
        startTimeNeedsRecalibration = false
        lastRecordedTime = .zero
        pauseTime = .zero
    }
    
    // MARK: - Pause/Resume
    
    func pause() {
        pauseTime = CMClockGetTime(CMClockGetHostTimeClock())
    }
    
    func resume() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let pauseDuration = CMTimeSubtract(now, pauseTime)
        timeOffset = CMTimeAdd(timeOffset, pauseDuration)
    }
    
    // MARK: - Processing
    
    struct ProcessingResult {
        let presentationTime: CMTime
        let shouldWrite: Bool
        let isFirstSample: Bool
    }
    
    /// Process a sample buffer timestamp and return adjusted time and write decision
    func processSampleTime(_ samplePresentationTime: CMTime) -> ProcessingResult {
        var isFirstSample = false
        
        // Handle first sample OR source switch recalibration
        if startTime == .zero {
            // First sample ever - set the baseline
            startTime = samplePresentationTime
            startTimeNeedsRecalibration = false
            isFirstSample = true
            AppLogger.recording.info("Recording started. First sample time: \(self.startTime.seconds)")
        } else if startTimeNeedsRecalibration {
            // Recalibrate
            recalibrate(currentPresentationTime: samplePresentationTime)
        }
        
        var presentationTime = samplePresentationTime
        if timeOffset != .zero {
            presentationTime = CMTimeSubtract(presentationTime, timeOffset)
        }
        
        // Track last recorded time
        lastRecordedTime = CMTimeSubtract(presentationTime, startTime)
        
        return ProcessingResult(
            presentationTime: presentationTime,
            shouldWrite: true, // Logic flow handled by caller checking writer state
            isFirstSample: isFirstSample
        )
    }
    
    private func recalibrate(currentPresentationTime: CMTime) {
        // CRITICAL FIX: Add a "safe gap" (100ms) to ensure strictly increasing timestamps
        let gap = CMTime(value: 100, timescale: 1000) // 100ms gap
        let lastAbsoluteTime = CMTimeAdd(startTime, lastRecordedTime)
        let targetNewTime = CMTimeAdd(lastAbsoluteTime, gap)

        // We want: samplePresentationTime - newTimeOffset = targetNewTime
        // So: newTimeOffset = samplePresentationTime - targetNewTime
        let newTimeOffset = CMTimeSubtract(currentPresentationTime, targetNewTime)

        timeOffset = newTimeOffset
        startTimeNeedsRecalibration = false

        AppLogger.recording.info("Time base recalibrated. Safe gap added: 100ms. New offset: \(self.timeOffset.seconds)s, continuing from: \(self.lastRecordedTime.seconds)s")
    }
    
    /// Adjust sample buffer timing based on current offset
    func adjustBufferTime(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        guard timeOffset != .zero else { return sample }
        
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)

        var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: Int(count))
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &info, entriesNeededOut: nil)

        for index in 0 ..< Int(count) {
            info[index].decodeTimeStamp = CMTimeSubtract(info[index].decodeTimeStamp, timeOffset)
            info[index].presentationTimeStamp = CMTimeSubtract(info[index].presentationTimeStamp, timeOffset)
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
