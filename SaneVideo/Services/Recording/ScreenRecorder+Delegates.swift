import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

// MARK: - SCRecordingOutputDelegate

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        AppLogger.recording.info("SCRecordingOutput started recording")
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        AppLogger.recording.info("SCRecordingOutput finished recording")
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput, didFailWithError error: Error
    ) {
        AppLogger.recording.error("SCRecordingOutput failed: \(error.localizedDescription)")
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        switch type {
        case .screen:
            publishScreenSample(sampleBuffer)

        case .audio:
            if !loggedScreenAudioFormat,
               let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                AppLogger.recording.info(
                    "Screen audio format sampleRate=\(asbdPointer.mSampleRate), " +
                    "channels=\(asbdPointer.mChannelsPerFrame), formatID=\(asbdPointer.mFormatID)"
                )
                loggedScreenAudioFormat = true
            }
            publishSystemAudioSample(sampleBuffer)

        case .microphone:
            publishMicSample(sampleBuffer)

        @unknown default:
            break
        }
    }
}

// MARK: - SCStreamDelegate (Error Handling)

extension ScreenRecorder {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            AppLogger.recording.error("Screen stream stopped with error: \(error.localizedDescription)")

            if !self.isStopping {
                self.onStop?(error)
            }

            self.activeStream = nil

            if !TestEnvironment.isTesting {
                let picker = SCContentSharingPicker.shared
                picker.isActive = false
                picker.remove(self)
            } else {
                AppLogger.recording.info(
                    "[TEST] ScreenRecorder: Skipping picker deactivation in error handler (test environment)"
                )
            }
        }
    }

    nonisolated func outputVideoEffectDidStartForStream(_ stream: SCStream) {
        Task { @MainActor in
            AppLogger.recording.info("Presenter Overlay STARTED. Hiding App PiP.")
            self.onPresenterOverlayChanged?(true)
        }
    }

    nonisolated func outputVideoEffectDidStopForStream(_ stream: SCStream) {
        Task { @MainActor in
            AppLogger.recording.info("Presenter Overlay STOPPED. Restoring App PiP.")
            self.onPresenterOverlayChanged?(false)
        }
    }
}

// MARK: - SCContentSharingPickerObserver

extension ScreenRecorder {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        nonisolated(unsafe) let unsafeStream = stream

        Task { @MainActor in
            AppLogger.recording.info("User selected content, starting capture...")
            self.onContentSelected?()

            if let stream = unsafeStream {
                let picker = SCContentSharingPicker.shared
                picker.setConfiguration(picker.defaultConfiguration, for: stream)
            }

            await handleContentSelected(filter: filter)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor in
            AppLogger.recording.warning("User cancelled screen picker")

            if let onStop = self.onStop {
                let cancelError = NSError(
                    domain: "SaneVideo",
                    code: -102,
                    userInfo: [NSLocalizedDescriptionKey: "User cancelled screen picker"]
                )
                onStop(cancelError)
            }

            self.activeStream = nil
            self.baseFilter = nil
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            AppLogger.recording.error("Picker failed to start: \(error.localizedDescription)")

            if let onStop = self.onStop {
                onStop(error)
            }

            self.activeStream = nil
            self.baseFilter = nil
        }
    }
}
