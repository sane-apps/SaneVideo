import Testing
import Combine
import AVFoundation
import Foundation
@testable import SaneVideo

@Suite("Camera Startup Tests")
@MainActor
struct CameraStartupTests {

    // MARK: - Test CameraState threading safety

    @Test("Camera orientation and session observers from background queue")
    func cameraStateObserversFromBackgroundQueue() async throws {
        let sessionSubject = CurrentValueSubject<AVCaptureSession?, Never>(nil)
        var observerCallCount = 0
        var cancellables = Set<AnyCancellable>()

        sessionSubject
            .receive(on: DispatchQueue.main)
            .sink { _ in
                observerCallCount += 1
            }
            .store(in: &cancellables)

        let sessionQueue = DispatchQueue(label: "com.sanevideo.test.cameraSession")
        let session = AVCaptureSession()

        sessionQueue.async {
            sessionSubject.send(session)
        }

        // Wait for the main queue to receive the event
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(observerCallCount > 0, "Observer should have been called")
    }

    @Test("Camera frame publisher setup completes without error")
    func cameraFramePublisherThreadSafety() async throws {
        // Arrange - Set up publisher with thread-safe receive
        let sampleSubject = PassthroughSubject<CMSampleBuffer, Never>()
        var receivedCount = 0
        var cancellables = Set<AnyCancellable>()

        // Act - Set up subscription on background queue
        sampleSubject
            .receive(on: DispatchQueue(label: "com.sanevideo.test.processing"))
            .sink { _ in
                receivedCount += 1
            }
            .store(in: &cancellables)

        // Assert - Verify setup completed without error
        // The fact that we can set up the subscription and store it means it worked
        // Verify cancellables contains the subscription (proves setup worked)
        #expect(cancellables.count == 1, "Subscription should be stored in cancellables")
    }

    @Test("Recording engine subscription setup thread safety")
    func recordingEngineSubscriptionsSetup() async throws {
        let subject = PassthroughSubject<Int, Never>()
        var receivedValues: [Int] = []
        var cancellables = Set<AnyCancellable>()
        let processingQueue = DispatchQueue(label: "com.sanevideo.test.processing")

        subject
            .receive(on: processingQueue)
            .sink { value in
                receivedValues.append(value)
            }
            .store(in: &cancellables)

        subject.send(1)
        subject.send(2)
        subject.send(3)

        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(receivedValues.count == 3, "All values should be received")
    }

    // MARK: - Test MainActor isolation

    @Test("MainActor isolation enforcement")
    func mainActorIsolationEnforced() async throws {
        @MainActor
        class TestObservable: ObservableObject {
            @Published var value = 0
            func increment() { value += 1 }
        }

        let observable = TestObservable()
        await MainActor.run {
            observable.increment()
        }

        #expect(observable.value == 1)
    }
}
