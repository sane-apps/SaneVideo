import AVFoundation
import Combine

class CameraOutputHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var sampleBufferSubject = PassthroughSubject<CMSampleBuffer, Never>()
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Crash fix: Ensure camera frames are sent on the main queue to prevent UI/threading violations.
        DispatchQueue.main.async {
            self.sampleBufferSubject.send(sampleBuffer)
        }
    }
}
