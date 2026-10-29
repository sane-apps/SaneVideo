// Undo and redo of the timeline edits people make most: split, trim, delete and duplicate.
// ProjectState has no clip-move operation (the magnetic timeline places clips by order), so there
// is no move case here.

import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

@Suite("Timeline Undo/Redo")
@MainActor
struct TimelineUndoRedoTests {
    private let state: ProjectState
    private let undoManager = UndoManager()
    private let clipA = VideoClip(url: URL(fileURLWithPath: "/tmp/a.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
    private let clipB = VideoClip(
        url: URL(fileURLWithPath: "/tmp/b.mov"),
        duration: CMTime(seconds: 6, preferredTimescale: 600),
        startTime: CMTime(seconds: 10, preferredTimescale: 600)
    )

    init() {
        state = ProjectState(projectStore: MockProjectStore())
        var project = VideoProject(name: "Undo")
        project.timeline.tracks = [Track(name: "Video", type: .video, clips: [clipA, clipB], zIndex: 0)]
        state.currentProject = project
        state.undoManager = undoManager
    }

    private var clips: [VideoClip] {
        state.currentProject?.timeline.tracks.first?.clips ?? []
    }

    /// Played length of each clip, in timeline order.
    private var layout: [Double] {
        clips.map { ($0.effectiveDuration.seconds * 1000).rounded() / 1000 }
    }

    @Test("Split at 4 s: undo restores the single clip, redo splits again")
    func splitUndoRedo() {
        state.splitClip(clipA, atTimelineTime: CMTime(seconds: 4, preferredTimescale: 600))
        #expect(layout == [4, 6, 6])

        undoManager.undo()
        #expect(layout == [10, 6])
        #expect(clips.first?.id == clipA.id)

        undoManager.redo()
        #expect(layout == [4, 6, 6])
    }

    @Test("Trim: undo restores the length and the next clip's start, redo trims again")
    func trimUndoRedo() {
        state.updateClipTrim(clipId: clipA.id, trimStart: nil, trimEnd: CMTime(seconds: 7, preferredTimescale: 600))
        #expect(layout == [7, 6])
        #expect(clips.last?.startTime.seconds == 7)

        undoManager.undo()
        #expect(layout == [10, 6])
        #expect(clips.last?.startTime.seconds == 10)

        undoManager.redo()
        #expect(layout == [7, 6])
    }

    @Test("Delete: undo puts the clip back in place, redo removes it again")
    func deleteUndoRedo() {
        state.deleteClip(clipA)
        #expect(clips.map(\.id) == [clipB.id])
        #expect(clips.first?.startTime == .zero)

        undoManager.undo()
        #expect(clips.map(\.id) == [clipA.id, clipB.id])
        #expect(clips.last?.startTime.seconds == 10)

        undoManager.redo()
        #expect(clips.map(\.id) == [clipB.id])
    }

    @Test("Duplicate: undo removes the copy, redo adds it back")
    func duplicateUndoRedo() {
        state.duplicateClip(clipB, atTime: CMTime(seconds: 16, preferredTimescale: 600))
        #expect(clips.count == 3)

        undoManager.undo()
        #expect(clips.map(\.id) == [clipA.id, clipB.id])

        undoManager.redo()
        #expect(clips.count == 3)
    }

    @Test("Several edits undo one step at a time, newest first")
    func editsUndoInOrder() {
        state.splitClip(clipA, atTimelineTime: CMTime(seconds: 4, preferredTimescale: 600))
        state.deleteClip(clipB)
        #expect(layout == [4, 6])

        undoManager.undo()
        #expect(layout == [4, 6, 6])

        undoManager.undo()
        #expect(layout == [10, 6])
        #expect(!undoManager.canUndo)
    }

    @Test("Undo while Clean Up's group is open restores the clip and does not crash when the group ends")
    func undoDuringOpenGroupDoesNotCrash() {
        state.beginUndoGroup("Clean Up")
        state.splitClip(clipA, atTimelineTime: CMTime(seconds: 4, preferredTimescale: 600))

        // ⌘Z mid-run: at nesting level 1, undo() closes the group itself.
        undoManager.undo()
        state.endUndoGroup()

        #expect(layout == [10, 6])
        #expect(undoManager.groupingLevel == 0)
    }
}
