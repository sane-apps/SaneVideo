//
//  DemoStudioModels.swift
//  SaneVideo
//
//  Local-first metadata and packaging models for product demos.
//

import CoreGraphics
import CoreMedia
import Foundation

enum PresentationPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case productWalkthrough
    case featureLaunch
    case supportTutorial
    case screenOnly
    case screenCameraBubble
    case screenCameraSidebar
    case verticalDemo
    case squareTeaser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .productWalkthrough: "Product Walkthrough"
        case .featureLaunch: "Feature Launch"
        case .supportTutorial: "Support Tutorial"
        case .screenOnly: "Screen Only"
        case .screenCameraBubble: "Camera Bubble"
        case .screenCameraSidebar: "Camera Sidebar"
        case .verticalDemo: "Vertical Demo"
        case .squareTeaser: "Square Teaser"
        }
    }

    var icon: String {
        switch self {
        case .productWalkthrough: return "rectangle.on.rectangle.circle.fill"
        case .featureLaunch: return "sparkles.rectangle.stack.fill"
        case .supportTutorial: return "questionmark.video.fill"
        case .screenOnly: return "display"
        case .screenCameraBubble: return "person.crop.circle.badge.video"
        case .screenCameraSidebar: return "rectangle.leadinghalf.filled"
        case .verticalDemo: return "rectangle.portrait.on.rectangle.portrait"
        case .squareTeaser: return "square.grid.2x2.fill"
        }
    }

    var summary: String {
        switch self {
        case .productWalkthrough:
            return "Balanced 16:9 product demo with room for captions, notes, and a polished master export."
        case .featureLaunch:
            return "Fast vertical-first setup for launch teasers, short updates, and social cutdowns."
        case .supportTutorial:
            return "Caption-friendly how-to layout tuned for slower pacing and clearer explanations."
        case .screenOnly:
            return "Pure screen capture when you want the product UI to fill the frame."
        case .screenCameraBubble:
            return "Adds a presenter bubble so viewers can see the person behind the walkthrough."
        case .screenCameraSidebar:
            return "Keeps the product large while reserving a clean column for presenter presence."
        case .verticalDemo:
            return "Optimized for portrait exports when the final destination is a phone-first feed."
        case .squareTeaser:
            return "Square framing for compact teasers, changelog clips, and thumbnail-style promos."
        }
    }

    var isDemoTemplate: Bool {
        switch self {
        case .productWalkthrough, .featureLaunch, .supportTutorial:
            true
        default:
            false
        }
    }

    var recommendedDemoPackSettings: DemoPackSettings {
        switch self {
        case .productWalkthrough, .screenOnly, .screenCameraBubble, .screenCameraSidebar:
            return DemoPackSettings(
                includeLandscapeVideo: true,
                includeVerticalVariant: false,
                includeSquareVariant: true,
                includeThumbnail: true,
                includeTranscriptText: true,
                includeTranscriptPDF: true,
                includeSpeakerNotes: true,
                includeChapters: true,
                includePublishMetadata: true
            )

        case .featureLaunch, .verticalDemo:
            return DemoPackSettings(
                includeLandscapeVideo: true,
                includeVerticalVariant: true,
                includeSquareVariant: true,
                includeThumbnail: true,
                includeTranscriptText: true,
                includeTranscriptPDF: false,
                includeSpeakerNotes: true,
                includeChapters: true,
                includePublishMetadata: true
            )

        case .supportTutorial:
            return DemoPackSettings(
                includeLandscapeVideo: true,
                includeVerticalVariant: false,
                includeSquareVariant: false,
                includeThumbnail: true,
                includeTranscriptText: true,
                includeTranscriptPDF: true,
                includeSpeakerNotes: true,
                includeChapters: true,
                includePublishMetadata: true
            )

        case .squareTeaser:
            return DemoPackSettings(
                includeLandscapeVideo: true,
                includeVerticalVariant: false,
                includeSquareVariant: true,
                includeThumbnail: true,
                includeTranscriptText: true,
                includeTranscriptPDF: false,
                includeSpeakerNotes: true,
                includeChapters: true,
                includePublishMetadata: true
            )
        }
    }

    var presenterLayout: PresenterOverlayLayout? {
        switch self {
        case .screenOnly:
            return nil
        case .productWalkthrough:
            return PresenterOverlayLayout(width: 320, height: 214, corner: .bottomRight)
        case .featureLaunch:
            return PresenterOverlayLayout(width: 240, height: 160, corner: .topRight)
        case .supportTutorial:
            return PresenterOverlayLayout(width: 320, height: 214, corner: .bottomLeft)
        case .screenCameraBubble:
            return PresenterOverlayLayout(width: 220, height: 147, corner: .bottomRight)
        case .screenCameraSidebar:
            return PresenterOverlayLayout(width: 280, height: 420, corner: .topRight)
        case .verticalDemo:
            return PresenterOverlayLayout(width: 220, height: 330, corner: .topRight)
        case .squareTeaser:
            return PresenterOverlayLayout(width: 240, height: 240, corner: .topRight)
        }
    }
}

enum PresenterOverlayCorner: String, Codable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct PresenterOverlayLayout: Codable, Equatable, Hashable, Sendable {
    var width: CGFloat
    var height: CGFloat
    var corner: PresenterOverlayCorner
    var margin: CGFloat = 40
}

struct SpeakerNotes: Codable, Equatable, Hashable, Sendable {
    var text: String = ""
    var fontSize: Double = 30
    var opacity: Double = 0.9
    var widthFraction: Double = 0.72
    var scrollSpeed: Double = 28
    var isMirrored: Bool = false
    var isVisible: Bool = false

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ChapterMarker: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var timestamp: Double
    var note: String?

    init(id: UUID = UUID(), title: String, timestamp: Double, note: String? = nil) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.note = note
    }
}

struct CommentaryMarker: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var concept: String?
    var title: String
    var startTime: Double
    var endTime: Double
    var scriptureReferences: String
    var sortOrder: Int?

    init(
        id: UUID = UUID(),
        concept: String? = nil,
        title: String,
        startTime: Double,
        endTime: Double,
        scriptureReferences: String = "",
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.concept = concept
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.scriptureReferences = scriptureReferences
        self.sortOrder = sortOrder
    }

    var duration: Double {
        max(endTime - startTime, 0)
    }

    var trimmedConcept: String? {
        let value = concept?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var sourceTimestampRange: String {
        "\(Self.timestampString(startTime))-\(Self.timestampString(endTime))"
    }

    var overlayText: String {
        let parts = [
            title.trimmingCharacters(in: .whitespacesAndNewlines),
            scriptureReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
        return parts.joined(separator: "\n")
    }

    static func parseLines(_ raw: String) -> [CommentaryMarker] {
        raw
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { index, line in
                let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard let rangePart = parts.first,
                      let (start, end) = parseRange(rangePart),
                      end > start
                else {
                    return nil
                }

                let concept = parts.count > 3 && !parts[1].isEmpty ? parts[1] : nil
                let titleIndex = parts.count > 3 ? 2 : 1
                let scriptureIndex = parts.count > 3 ? 3 : 2
                let title = parts.count > titleIndex && !parts[titleIndex].isEmpty ? parts[titleIndex] : "Commentary Point"
                let scriptureReferences = parts.count > scriptureIndex ? parts[scriptureIndex] : ""
                return CommentaryMarker(
                    concept: concept,
                    title: title,
                    startTime: start,
                    endTime: end,
                    scriptureReferences: scriptureReferences,
                    sortOrder: index
                )
            }
            .ordered()
    }

    static func serializeLines(_ markers: [CommentaryMarker]) -> String {
        markers
            .ordered()
            .map { marker in
                let range = "\(timestampString(marker.startTime))-\(timestampString(marker.endTime))"
                let scripture = marker.scriptureReferences.trimmingCharacters(in: .whitespacesAndNewlines)
                let concept = marker.trimmedConcept
                if let concept {
                    if scripture.isEmpty {
                        return "\(range) | \(concept) | \(marker.title)"
                    }
                    return "\(range) | \(concept) | \(marker.title) | \(scripture)"
                }
                if scripture.isEmpty {
                    return "\(range) | \(marker.title)"
                }
                return "\(range) | \(marker.title) | \(scripture)"
            }
            .joined(separator: "\n")
    }

    static func ordered(_ markers: [CommentaryMarker]) -> [CommentaryMarker] {
        markers
            .enumerated()
            .sorted { lhs, rhs in
                let leftOrder = lhs.element.sortOrder ?? lhs.offset
                let rightOrder = rhs.element.sortOrder ?? rhs.offset
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                if lhs.element.startTime == rhs.element.startTime {
                    return lhs.element.endTime < rhs.element.endTime
                }
                return lhs.element.startTime < rhs.element.startTime
            }
            .map(\.element)
    }

    private static func parseRange(_ raw: String) -> (Double, Double)? {
        let normalized = raw.replacingOccurrences(of: "–", with: "-")
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2,
              let start = parseTimestamp(String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)),
              let end = parseTimestamp(String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return (start, end)
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let pieces = raw.split(separator: ":").compactMap { Double($0) }

        switch pieces.count {
        case 1:
            return pieces[0]
        case 2:
            return (pieces[0] * 60) + pieces[1]
        case 3:
            return (pieces[0] * 3600) + (pieces[1] * 60) + pieces[2]
        default:
            return nil
        }
    }

    private static func timestampString(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private extension Array where Element == CommentaryMarker {
    func ordered() -> [CommentaryMarker] {
        CommentaryMarker.ordered(self)
    }
}

enum WorkflowPack: String, Codable, CaseIterable, Identifiable, Sendable {
    case commentary
    case meetingReview
    case salesCoach
    case teachingStudy
    case supportQA
    case podcastRepurpose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commentary: return "Commentary"
        case .meetingReview: return "Meeting Review"
        case .salesCoach: return "Sales Coach"
        case .teachingStudy: return "Teaching / Study"
        case .supportQA: return "Support QA"
        case .podcastRepurpose: return "Podcast Repurpose"
        }
    }

    var icon: String {
        switch self {
        case .commentary: return "quote.bubble"
        case .meetingReview: return "person.3.sequence"
        case .salesCoach: return "chart.bar.xaxis"
        case .teachingStudy: return "book.closed"
        case .supportQA: return "checklist"
        case .podcastRepurpose: return "mic"
        }
    }

    var summary: String {
        switch self {
        case .commentary:
            return "Group the source into critique-ready concepts with grounded timestamps."
        case .meetingReview:
            return "Pull out decisions, disagreements, and action items from the transcript."
        case .salesCoach:
            return "Find objections, strong moments, and coach-up opportunities."
        case .teachingStudy:
            return "Break long teaching into grouped ideas, notes, and study moments."
        case .supportQA:
            return "Surface issue moments, steps, and review notes from support footage."
        case .podcastRepurpose:
            return "Turn long-form conversation into reusable topic clusters and short clips."
        }
    }
}

struct WorkflowBrief: Codable, Equatable, Hashable, Sendable {
    var workflow: WorkflowPack = .commentary
    var instructions: String = ""
    var voiceBriefSummary: String = ""
    var maxMoments: Int = 6

    var hasContent: Bool {
        !combinedPrompt.isEmpty
    }

    var combinedPrompt: String {
        [instructions, voiceBriefSummary]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct CommentaryPlanItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var concept: String
    var claim: String
    var supportingReferences: String
    var sourceExcerpt: String
    var startTime: Double
    var endTime: Double
    var confidence: Double
    var sortOrder: Int?

    init(
        id: UUID = UUID(),
        concept: String,
        claim: String,
        supportingReferences: String = "",
        sourceExcerpt: String = "",
        startTime: Double,
        endTime: Double,
        confidence: Double = 0.5,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.concept = concept
        self.claim = claim
        self.supportingReferences = supportingReferences
        self.sourceExcerpt = sourceExcerpt
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.sortOrder = sortOrder
    }

    var trimmedConcept: String {
        concept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedClaim: String {
        claim.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sourceTimestampRange: String {
        "\(Self.timestampString(startTime))-\(Self.timestampString(endTime))"
    }

    var commentaryMarker: CommentaryMarker {
        CommentaryMarker(
            id: id,
            concept: trimmedConcept.isEmpty ? nil : trimmedConcept,
            title: trimmedClaim.isEmpty ? "Commentary Point" : trimmedClaim,
            startTime: startTime,
            endTime: endTime,
            scriptureReferences: supportingReferences.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: sortOrder
        )
    }

    static func ordered(_ items: [CommentaryPlanItem]) -> [CommentaryPlanItem] {
        items
            .enumerated()
            .sorted { lhs, rhs in
                let leftOrder = lhs.element.sortOrder ?? lhs.offset
                let rightOrder = rhs.element.sortOrder ?? rhs.offset
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                if lhs.element.startTime == rhs.element.startTime {
                    return lhs.element.endTime < rhs.element.endTime
                }
                return lhs.element.startTime < rhs.element.startTime
            }
            .map(\.element)
    }

    static func fromMarkers(_ markers: [CommentaryMarker]) -> [CommentaryPlanItem] {
        CommentaryMarker.ordered(markers)
            .enumerated()
            .map { index, marker in
                CommentaryPlanItem(
                    id: marker.id,
                    concept: marker.trimmedConcept ?? "Commentary",
                    claim: marker.title,
                    supportingReferences: marker.scriptureReferences,
                    sourceExcerpt: marker.title,
                    startTime: marker.startTime,
                    endTime: marker.endTime,
                    confidence: 0.7,
                    sortOrder: marker.sortOrder ?? index
                )
            }
    }

    private static func timestampString(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

enum CommentaryWorkflowPlanner {
    private struct TranscriptMoment: Equatable {
        let startTime: Double
        let endTime: Double
        let text: String
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from", "has", "have",
        "how", "if", "in", "into", "is", "it", "its", "of", "on", "or", "our", "that", "the",
        "their", "them", "there", "they", "this", "to", "was", "we", "what", "when", "where",
        "which", "who", "why", "with", "you", "your"
    ]

    static func buildDraft(
        from captions: [Caption],
        brief: WorkflowBrief,
        existingMarkers: [CommentaryMarker] = []
    ) -> [CommentaryPlanItem] {
        let orderedMarkers = CommentaryMarker.ordered(existingMarkers)
        if !brief.hasContent && !orderedMarkers.isEmpty {
            return CommentaryPlanItem.fromMarkers(orderedMarkers)
        }

        let moments = buildMoments(from: captions)
        guard !moments.isEmpty else {
            return CommentaryPlanItem.fromMarkers(orderedMarkers)
        }

        let maxMoments = min(max(brief.maxMoments, 1), 12)
        let promptKeywords = keywords(from: brief.combinedPrompt)
        let requestedConcepts = focusPhrases(from: brief)
        var usedIndices: Set<Int> = []
        var items: [CommentaryPlanItem] = []

        for concept in requestedConcepts.prefix(maxMoments) {
            let conceptKeywords = keywords(from: concept)
            guard !conceptKeywords.isEmpty,
                  let match = bestMomentIndex(
                    for: conceptKeywords,
                    in: moments,
                    excluding: usedIndices
                  )
            else {
                continue
            }

            usedIndices.insert(match.index)
            items.append(
                makeItem(
                    from: moments[match.index],
                    concept: formatConcept(concept),
                    confidence: min(0.95, 0.55 + match.score * 0.08),
                    sortOrder: items.count
                )
            )
        }

        let rankedIndices = moments.indices
            .filter { !usedIndices.contains($0) }
            .sorted {
                relevanceScore(for: moments[$0], promptKeywords: promptKeywords)
                    > relevanceScore(for: moments[$1], promptKeywords: promptKeywords)
            }

        for index in rankedIndices.prefix(max(0, maxMoments - items.count)) {
            let moment = moments[index]
            let concept = inferredConcept(from: moment.text, fallbackIndex: items.count + 1)
            let confidence = promptKeywords.isEmpty ? 0.45 : min(0.88, 0.42 + relevanceScore(for: moment, promptKeywords: promptKeywords) * 0.1)
            items.append(
                makeItem(
                    from: moment,
                    concept: concept,
                    confidence: confidence,
                    sortOrder: items.count
                )
            )
        }

        return CommentaryPlanItem.ordered(items)
    }

    private static func buildMoments(from captions: [Caption]) -> [TranscriptMoment] {
        let sortedCaptions = captions.sorted { $0.startTime < $1.startTime }
        guard !sortedCaptions.isEmpty else { return [] }

        var moments: [TranscriptMoment] = []
        var currentStart: Double?
        var currentEnd = 0.0
        var currentText = ""
        var currentWordCount = 0

        func flushCurrentMoment() {
            guard let currentStart, !currentText.isEmpty else { return }
            moments.append(
                TranscriptMoment(
                    startTime: currentStart,
                    endTime: currentEnd,
                    text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        for caption in sortedCaptions {
            let text = caption.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let startSeconds = caption.startTime.seconds
            let endSeconds = caption.endTime.seconds
            let gap = currentStart == nil ? 0 : max(0, startSeconds - currentEnd)
            let appendedText = currentText.isEmpty ? text : "\(currentText) \(text)"
            let wordCount = appendedText.split(whereSeparator: \.isWhitespace).count
            let shouldBreak = gap > 2.5 || wordCount > 32 || endsSentence(text)

            if currentStart == nil {
                currentStart = startSeconds
                currentEnd = endSeconds
                currentText = text
                currentWordCount = text.split(whereSeparator: \.isWhitespace).count
                if shouldBreak {
                    flushCurrentMoment()
                    currentStart = nil
                    currentEnd = 0
                    currentText = ""
                    currentWordCount = 0
                }
                continue
            }

            currentEnd = endSeconds
            currentText = appendedText
            currentWordCount = wordCount

            if shouldBreak || currentWordCount > 32 {
                flushCurrentMoment()
                currentStart = nil
                currentEnd = 0
                currentText = ""
                currentWordCount = 0
            }
        }

        flushCurrentMoment()
        return moments.filter { !$0.text.isEmpty && $0.endTime > $0.startTime }
    }

    private static func focusPhrases(from brief: WorkflowBrief) -> [String] {
        let prompt = brief.combinedPrompt
        guard !prompt.isEmpty else { return [] }

        let normalized = prompt
            .replacingOccurrences(of: " and ", with: ", ")
            .replacingOccurrences(of: " then ", with: ", ")
        let pieces = normalized
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return pieces.compactMap { phrase in
            let words = phrase.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty else { return nil }
            if words.count > 6 {
                return nil
            }
            return phrase
        }
    }

    private static func bestMomentIndex(
        for keywords: Set<String>,
        in moments: [TranscriptMoment],
        excluding usedIndices: Set<Int>
    ) -> (index: Int, score: Double)? {
        var best: (index: Int, score: Double)?

        for index in moments.indices where !usedIndices.contains(index) {
            let overlap = Double(keywords.intersection(self.keywords(from: moments[index].text)).count)
            guard overlap > 0 else { continue }

            let score = overlap + min(Double(moments[index].text.count) / 160.0, 0.6)
            if let best, best.score >= score {
                continue
            }
            best = (index, score)
        }

        return best
    }

    private static func relevanceScore(
        for moment: TranscriptMoment,
        promptKeywords: Set<String>
    ) -> Double {
        let textKeywords = keywords(from: moment.text)
        let overlap = Double(promptKeywords.intersection(textKeywords).count)
        let density = min(Double(textKeywords.count) / 8.0, 1.2)
        let punctuationBoost = moment.text.contains("?") ? 0.2 : 0.0
        return overlap * 2.0 + density + punctuationBoost
    }

    private static func makeItem(
        from moment: TranscriptMoment,
        concept: String,
        confidence: Double,
        sortOrder: Int
    ) -> CommentaryPlanItem {
        CommentaryPlanItem(
            concept: concept,
            claim: claimText(from: moment.text),
            supportingReferences: "",
            sourceExcerpt: moment.text,
            startTime: max(0, moment.startTime),
            endTime: moment.endTime,
            confidence: confidence,
            sortOrder: sortOrder
        )
    }

    private static func inferredConcept(from text: String, fallbackIndex: Int) -> String {
        let tokens = Array(keywords(from: text).prefix(3))
        guard !tokens.isEmpty else {
            return "Moment \(fallbackIndex)"
        }
        return tokens
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func claimText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 96 else { return trimmed }
        let prefix = String(trimmed.prefix(96))
        if let boundary = prefix.lastIndex(where: { ".!?,".contains($0) }) {
            return String(prefix[...boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keywords(from raw: String) -> Set<String> {
        let lowered = raw.lowercased()
        let tokens = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        return Set(tokens)
    }

    private static func formatConcept(_ raw: String) -> String {
        raw
            .split(whereSeparator: \.isWhitespace)
            .prefix(4)
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?".contains(last)
    }
}

struct DemoPackSettings: Codable, Equatable, Hashable, Sendable {
    var includeLandscapeVideo: Bool = true
    var includeVerticalVariant: Bool = false
    var includeSquareVariant: Bool = false
    var includeThumbnail: Bool = true
    var includeTranscriptText: Bool = true
    var includeTranscriptPDF: Bool = true
    var includeSpeakerNotes: Bool = true
    var includeChapters: Bool = true
    var includePublishMetadata: Bool = true
}

struct PublishMetadata: Codable, Equatable, Hashable, Sendable {
    var title: String = ""
    var subtitle: String = ""
    var description: String = ""
    var callToAction: String = ""

    static func `default`(for projectName: String) -> PublishMetadata {
        PublishMetadata(
            title: projectName,
            subtitle: "",
            description: "",
            callToAction: "Learn more"
        )
    }
}

struct InteractionOverlayStyle: Codable, Equatable, Hashable, Sendable {
    var highlightClicks: Bool = true
    var spotlightCursor: Bool = true
    var showKeystrokes: Bool = true
    var clickRingScale: Double = 1.0
    var spotlightOpacity: Double = 0.25
}
