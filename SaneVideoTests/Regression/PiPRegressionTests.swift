// The camera bubble window must float over other apps on every space, stay out of
// the screen-share picker and captures, and be movable and resizable.

import AppKit
@testable import SaneVideo
import Testing

@Suite("PiP Camera Window")
@MainActor
struct PiPRegressionTests {
    @Test("PiP window floats, joins all spaces, never hides, stays out of capture and can be moved and resized")
    func pipWindowConfiguration() {
        let pipWindow = PiPCameraWindow()
        defer { pipWindow.close() }

        // Visibility while recording other apps (regression: window vanished on focus switch).
        #expect(pipWindow.level == .floating)
        #expect(pipWindow.styleMask.contains(.nonactivatingPanel))
        #expect(pipWindow.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(pipWindow.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!pipWindow.hidesOnDeactivate)

        // Regression: window appeared in the screen-share picker.
        #expect(pipWindow.sharingType == .none)
        // Regression: crash when closing after screen share ended.
        #expect(!pipWindow.isReleasedWhenClosed)

        #expect(pipWindow.styleMask.contains(.resizable))
        #expect(pipWindow.isMovableByWindowBackground)
    }
}
