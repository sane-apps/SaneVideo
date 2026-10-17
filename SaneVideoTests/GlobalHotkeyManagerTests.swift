// Option-Command-R and Option-Command-P are held only when they can act, so Safari,
// Xcode and other apps keep those keys the rest of the time.

@testable import SaneVideo
import Testing

@Suite("Global Hot Keys")
struct GlobalHotkeyManagerTests {
    @Test("Record key only while the recorder is open or a take runs; pause key only while recording")
    func keysHeldOnlyWhenUsable() {
        let editor = GlobalHotkeyManager.keysToHold(recorderOpen: false, isRecording: false)
        #expect(!editor.record)
        #expect(!editor.pause)

        let recorder = GlobalHotkeyManager.keysToHold(recorderOpen: true, isRecording: false)
        #expect(recorder.record)
        #expect(!recorder.pause)

        let hiddenTake = GlobalHotkeyManager.keysToHold(recorderOpen: false, isRecording: true)
        #expect(hiddenTake.record)
        #expect(hiddenTake.pause)
    }
}
