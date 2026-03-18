import AVFoundation
import Foundation

enum CommentaryReelBuildError: LocalizedError {
    case noCurrentProject
    case noCommentaryMarkers
    case requiresSingleVideoClip
    case markerOutOfBounds(index: Int)

    var errorDescription: String? {
        switch self {
        case .noCurrentProject:
            return "Open a project first."
        case .noCommentaryMarkers:
            return "Add commentary cues in Demo Studio first."
        case .requiresSingleVideoClip:
            return "Commentary Reel currently works on projects with one main video clip."
        case let .markerOutOfBounds(index):
            return "Commentary cue \(index) is outside the source clip range."
        }
    }
}

@MainActor
extension ProjectState {
    private enum CommentaryLayout {
        static let captionBottomY = -0.68
        static let overlayLeadIn = 0.2
        static let overlayMinDuration = 2.5
        static let overlayMaxDuration = 7.0
        static let overlayPosition = CGPoint(x: 0.5, y: 0.76)
        static let maxLeadSeconds = 18.0
        static let maxTailSeconds = 18.0
        static let minimumClipDuration = 10.0
    }

    func buildCommentaryReel() throws -> VideoProject {
        guard let sourceProject = currentProject else {
            throw CommentaryReelBuildError.noCurrentProject
        }

        let reel = try makeCommentaryReelProject(from: sourceProject)
        projects.insert(reel, at: 0)
        updateCurrentProject(reel)
        saveProject(reel)

        AppLogger.project.info("Built commentary reel '\(reel.name)' from '\(sourceProject.name)'")
        return reel
    }

    private func makeCommentaryReelProject(from sourceProject: VideoProject) throws -> VideoProject {
        let sourceMarkers = sourceProject.commentaryMarkers.isEmpty
            ? sourceProject.commentaryPlanItems.map(\.commentaryMarker)
            : sourceProject.commentaryMarkers
        let markers = CommentaryMarker.ordered(sourceMarkers)
        guard !markers.isEmpty else {
            throw CommentaryReelBuildError.noCommentaryMarkers
        }

        let sourceClip = try sourceVideoClip(in: sourceProject)
        let minTime = sourceClip.trimStart.seconds
        let maxTime = sourceClip.trimEnd.seconds

        var reelClips: [VideoClip] = []
        var reelChapters: [ChapterMarker] = []
        var reelCursor = 0.0

        for (index, marker) in markers.enumerated() {
            guard let clipRange = commentaryClipRange(for: marker, in: sourceClip, minTime: minTime, maxTime: maxTime) else {
                throw CommentaryReelBuildError.markerOutOfBounds(index: index + 1)
            }

            var segment = sourceClip.copy(
                newId: UUID(),
                trimStart: CMTime(seconds: clipRange.lowerBound, preferredTimescale: 600),
                trimEnd: CMTime(seconds: clipRange.upperBound, preferredTimescale: 600)
            )
            segment.startTime = CMTime(seconds: reelCursor, preferredTimescale: 600)
            segment.overlays = []
            if let overlay = makeCommentaryOverlay(for: marker) {
                segment.overlays = [overlay]
            }

            reelClips.append(segment)
            reelChapters.append(
                ChapterMarker(
                    title: chapterTitle(for: marker),
                    timestamp: reelCursor,
                    note: chapterNote(for: marker)
                )
            )
            reelCursor += segment.effectiveDuration.seconds
        }

        var reel = VideoProject(
            id: UUID(),
            name: generateUniqueProjectName(baseName: "\(sourceProject.name) Commentary Reel"),
            createdAt: Date()
        )
        reel.timeline = Timeline(tracks: [
            Track(name: "Commentary Reel", type: .video, clips: reelClips, zIndex: 0)
        ])
        reel.modifiedAt = Date()
        reel.captionStyleName = sourceProject.captionStyleName
        reel.captionOffset = CGSize(width: sourceProject.captionOffset.width, height: CommentaryLayout.captionBottomY)
        reel.captionFontName = sourceProject.captionFontName
        reel.presentationPreset = sourceProject.presentationPreset
        reel.speakerNotes = sourceProject.speakerNotes
        reel.chapterMarkers = reelChapters
        reel.workflowBrief = sourceProject.workflowBrief
        reel.commentaryPlanItems = sourceProject.commentaryPlanItems.isEmpty
            ? CommentaryPlanItem.fromMarkers(markers)
            : CommentaryPlanItem.ordered(sourceProject.commentaryPlanItems)
        reel.commentaryMarkers = markers
        reel.demoPackSettings = sourceProject.demoPackSettings
        reel.publishMetadata = sourceProject.publishMetadata
        reel.publishMetadata.title = reel.name
        reel.currentTime = 0.0
        reel.scrollOffset = 0.0
        reel.zoomLevel = 1.0

        return reel
    }

    private func sourceVideoClip(in project: VideoProject) throws -> VideoClip {
        let clips = project.timeline.tracks
            .filter { $0.type == .video }
            .flatMap(\.clips)

        guard clips.count == 1, let sourceClip = clips.first else {
            throw CommentaryReelBuildError.requiresSingleVideoClip
        }

        return sourceClip
    }

    private func commentaryClipRange(
        for marker: CommentaryMarker,
        in sourceClip: VideoClip,
        minTime: Double,
        maxTime: Double
    ) -> ClosedRange<Double>? {
        guard marker.startTime >= minTime, marker.endTime <= maxTime, marker.endTime > marker.startTime else {
            return nil
        }

        let captions = sourceClip.captions.sorted { $0.startTime < $1.startTime }
        guard !captions.isEmpty else {
            let clipStart = max(minTime, marker.startTime - 8.0)
            let clipEnd = min(maxTime, max(marker.endTime, clipStart + CommentaryLayout.minimumClipDuration))
            return clipStart...clipEnd
        }

        let clipStart = contextualClipStart(
            for: marker.startTime,
            captions: captions,
            minTime: minTime
        )
        let clipEnd = contextualClipEnd(
            for: marker.endTime,
            clipStart: clipStart,
            captions: captions,
            maxTime: maxTime
        )

        guard clipEnd > clipStart else { return nil }
        return clipStart...clipEnd
    }

    private func contextualClipStart(
        for focusStart: Double,
        captions: [Caption],
        minTime: Double
    ) -> Double {
        guard let startIndex = captions.firstIndex(where: { $0.endTime.seconds >= focusStart }) else {
            return max(minTime, focusStart)
        }

        var index = startIndex
        var sentenceBoundariesSeen = 0

        while index > 0 {
            let previous = captions[index - 1]
            if focusStart - previous.startTime.seconds > CommentaryLayout.maxLeadSeconds {
                break
            }

            index -= 1
            if endsSentence(in: previous.text) {
                sentenceBoundariesSeen += 1
                if sentenceBoundariesSeen >= 2 {
                    break
                }
            }
        }

        return max(minTime, captions[index].startTime.seconds)
    }

    private func contextualClipEnd(
        for focusEnd: Double,
        clipStart: Double,
        captions: [Caption],
        maxTime: Double
    ) -> Double {
        guard let endIndex = captions.lastIndex(where: { $0.startTime.seconds <= focusEnd }) else {
            return min(maxTime, max(focusEnd, clipStart + CommentaryLayout.minimumClipDuration))
        }

        var index = endIndex

        while index < captions.count - 1 {
            let current = captions[index]
            if current.endTime.seconds >= focusEnd && endsSentence(in: current.text) {
                break
            }

            let next = captions[index + 1]
            if next.endTime.seconds - focusEnd > CommentaryLayout.maxTailSeconds {
                break
            }
            index += 1
        }

        var clipEnd = min(maxTime, captions[index].endTime.seconds)

        while index < captions.count - 1, clipEnd - clipStart < CommentaryLayout.minimumClipDuration {
            let next = captions[index + 1]
            if next.endTime.seconds - focusEnd > CommentaryLayout.maxTailSeconds {
                break
            }
            index += 1
            clipEnd = min(maxTime, captions[index].endTime.seconds)
        }

        return max(focusEnd, clipEnd)
    }

    private func chapterTitle(for marker: CommentaryMarker) -> String {
        guard let concept = marker.trimmedConcept else {
            return marker.title
        }
        return "\(concept): \(marker.title)"
    }

    private func chapterNote(for marker: CommentaryMarker) -> String? {
        let parts = [
            marker.sourceTimestampRange,
            marker.scriptureReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private func commentaryOverlayText(for marker: CommentaryMarker) -> String {
        let parts = [
            marker.trimmedConcept,
            marker.sourceTimestampRange,
            marker.title.trimmingCharacters(in: .whitespacesAndNewlines),
            marker.scriptureReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        ].compactMap { value -> String? in
            guard let value else { return nil }
            return value.isEmpty ? nil : value
        }
        return parts.joined(separator: "\n")
    }

    private func makeCommentaryOverlay(for marker: CommentaryMarker) -> VideoClip.VideoOverlay? {
        let text = commentaryOverlayText(for: marker).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let overlayDuration = min(
            marker.duration,
            max(
                CommentaryLayout.overlayMinDuration,
                min(CommentaryLayout.overlayMaxDuration, marker.duration * 0.75)
            )
        )
        return VideoClip.VideoOverlay(
            text: text,
            startTime: CommentaryLayout.overlayLeadIn,
            duration: overlayDuration,
            position: CommentaryLayout.overlayPosition,
            scale: 1.0,
            rotation: 0.0
        )
    }

    private func endsSentence(in text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return ".!?".contains(last)
    }
}
