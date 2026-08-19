//
//  DemoStudioSheet.swift
//  SaneVideo
//
//  Local-only project metadata, notes, and packaging controls for product demos.
//

import SwiftUI

struct DemoStudioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var presentationPreset: PresentationPreset = .productWalkthrough
    @State private var speakerNotesText = ""
    @State private var speakerNotesFontSize = 30.0
    @State private var speakerNotesOpacity = 0.9
    @State private var speakerNotesWidth = 0.72
    @State private var speakerNotesScrollSpeed = 28.0
    @State private var speakerNotesMirrored = false
    @State private var teleprompterVisible = false

    @State private var publishTitle = ""
    @State private var publishSubtitle = ""
    @State private var publishDescription = ""
    @State private var publishCTA = ""

    @State private var chapterLines = ""
    @State private var commentaryLines = ""
    @State private var workflowPack: WorkflowPack = .commentary
    @State private var workflowInstructions = ""
    @State private var voiceBriefSummary = ""
    @State private var workflowMaxMoments = 6
    @State private var commentaryPlanItems: [CommentaryPlanItem] = []
    @State private var showAdvancedCueDraft = false
    @State private var isGeneratingCommentaryPlan = false

    @State private var includeLandscapeVideo = true
    @State private var includeVerticalVariant = false
    @State private var includeSquareVariant = false
    @State private var includeThumbnail = true
    @State private var includeTranscriptText = true
    @State private var includeTranscriptPDF = true
    @State private var includeSpeakerNotes = true
    @State private var includeChapters = true
    @State private var includePublishMetadata = true

    @State private var loadedProjectID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Demo Studio",
                subtitle: "Privacy-first notes, metadata, and local export settings",
                icon: "note.text",
                dismissAction: { dismiss() },
                accessibilityID: "demo_studio.close"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FeatureCallout(
                        title: "Everything here stays local",
                        message: "Speaker notes, teleprompter settings, chapters, and demo-pack metadata stay with the project locally. If you enable iCloud Sync, Apple can sync that project between your Macs.",
                        icon: "lock.shield.fill"
                    )
                    presentationSection
                    speakerNotesSection
                    publishSection
                    chapterSection
                    workflowBriefSection
                    commentarySection
                    demoPackSection
                }
                .padding(20)
            }

            Divider()

            SheetFooter(
                actionTitle: "Save Demo Studio",
                cancelID: "demo_studio.cancel",
                actionID: "demo_studio.save",
                onCancel: { dismiss() },
                onAction: { saveChanges(dismissAfter: true) }
            )
        }
        .frame(width: 680, height: 760)
        .sanePanel(radius: 18, emphasized: true, accent: Theme.Colors.accentSoft)
        .task {
            if appState.currentProject == nil {
                appState.projectState.startNewProject()
            }
            loadProject()
        }
        .onChange(of: appState.currentProject?.id) { _, _ in
            loadProject()
        }
    }

    private var presentationSection: some View {
        section("Presentation Preset", subtitle: "Use presets to keep demo exports consistent.") {
            Picker("Presentation Preset", selection: $presentationPreset) {
                ForEach(PresentationPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .help("Choose the layout and default export mix that matches this demo.")

            HelperText(
                text: presentationPreset.summary,
                icon: presentationPreset.icon
            )

            Button("Use Preset Demo Pack Defaults") {
                applyDemoPackSettings(presentationPreset.recommendedDemoPackSettings)
            }
            .buttonStyle(.bordered)
            .help("Applies the recommended mix of master video, social variants, transcript, notes, chapters, and metadata for this preset.")

            HelperText(
                text: "Use this when you want the current preset to immediately set sensible demo-pack defaults.",
                icon: "shippingbox.fill"
            )
        }
    }

    private var speakerNotesSection: some View {
        section("Speaker Notes", subtitle: "Stored in the project only. No sync, no hosting.") {
            HelperText(
                text: "Write the script you want in front of you while recording. The teleprompter window is excluded from capture.",
                icon: "text.alignleft"
            )

            TextEditor(text: $speakerNotesText)
                .font(Theme.Typography.body)
                .frame(minHeight: 160)
                .padding(8)
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.cardBackground.opacity(0.92))
                .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)

            HStack(spacing: 16) {
                sliderField(title: "Font", value: $speakerNotesFontSize, range: 18...56, step: 1, format: "%.0f")
                sliderField(title: "Opacity", value: $speakerNotesOpacity, range: 0.35...1.0, step: 0.05, format: "%.2f")
            }

            HStack(spacing: 16) {
                sliderField(title: "Width", value: $speakerNotesWidth, range: 0.5...0.95, step: 0.05, format: "%.2f")
                sliderField(title: "Scroll Speed", value: $speakerNotesScrollSpeed, range: 10...80, step: 1, format: "%.0f")
            }

            LabeledToggleRow(
                title: "Mirror text for camera teleprompter setups",
                message: "Turn this on if you are reading the notes through a mirrored teleprompter glass in front of the camera.",
                isOn: $speakerNotesMirrored
            )

            LabeledToggleRow(
                title: "Show teleprompter while recording",
                message: "Opens the local teleprompter overlay. It stays out of the recording capture.",
                isOn: $teleprompterVisible
            )

            HStack(spacing: 12) {
                Button(teleprompterVisible ? "Save and Keep Visible" : "Save and Hide Teleprompter") {
                    saveChanges(dismissAfter: false)
                }
                .buttonStyle(.bordered)
                .help("Save your notes and keep the teleprompter in its current visibility state.")

                Button(teleprompterVisible ? "Hide Teleprompter Now" : "Show Teleprompter Now") {
                    teleprompterVisible.toggle()
                    saveChanges(dismissAfter: false)
                }
                .buttonStyle(.borderedProminent)
                .help("Toggles the teleprompter immediately using the current notes and appearance settings.")
            }
        }
    }

    private var publishSection: some View {
        section("Publish Metadata", subtitle: "Used for the local demo pack and optional third-party uploads.") {
            HelperText(
                text: "Fill this out once and SaneVideo can reuse it for demo-pack text files and optional upload forms.",
                icon: "text.badge.checkmark"
            )

            TextField("Title", text: $publishTitle)
                .textFieldStyle(.roundedBorder)
                .help("Main title for the exported video and metadata bundle.")

            TextField("Subtitle", text: $publishSubtitle)
                .textFieldStyle(.roundedBorder)
                .help("Short supporting line that clarifies the audience, release, or use case.")

            TextField("Call To Action", text: $publishCTA)
                .textFieldStyle(.roundedBorder)
                .help("Simple next step such as Learn more or Book a demo.")

            TextEditor(text: $publishDescription)
                .font(Theme.Typography.body)
                .frame(minHeight: 120)
                .padding(8)
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.cardBackground.opacity(0.92))
                .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)

            HelperText(
                text: "Use the description for the fuller launch copy, onboarding summary, or support context you want to ship with the demo.",
                icon: "doc.text.magnifyingglass"
            )
        }
    }

    private var chapterSection: some View {
        section("Chapters", subtitle: "Use one line per chapter: `mm:ss Title`. Leave empty to auto-build from clip boundaries.") {
            HelperText(
                text: "Chapters make the final bundle easier to skim and help you repurpose a long demo into smaller segments later.",
                icon: "list.number"
            )

            TextEditor(text: $chapterLines)
                .font(Theme.Typography.metaMonospaced)
                .frame(minHeight: 120)
                .padding(8)
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.cardBackground.opacity(0.92))
                .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)

            Button("Use Clip Boundaries") {
                chapterLines = clipBoundaryChapterLines()
            }
            .buttonStyle(.bordered)
            .help("Generates starter chapters from the current clip layout in the timeline.")
        }
    }

    private var workflowBriefSection: some View {
        section("Workflow Brief", subtitle: "Describe what you want SaneVideo to pull from the transcript before it becomes a reel.") {
            Picker("Workflow", selection: $workflowPack) {
                ForEach(WorkflowPack.allCases) { workflow in
                    Label(workflow.displayName, systemImage: workflow.icon)
                        .tag(workflow)
                }
            }
            .pickerStyle(.menu)
            .help("This changes how the draft is framed, even before a dedicated workflow pack exists.")

            HelperText(
                text: workflowPack.summary,
                icon: workflowPack.icon
            )

            TextEditor(text: $workflowInstructions)
                .font(Theme.Typography.body)
                .frame(minHeight: 92)
                .padding(8)
                .foregroundStyle(Theme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.cardBackground.opacity(0.92))
                .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)

            HelperText(
                text: "Write the focus in plain English. Example: group the errors by concept, keep the source timestamps visible, and start each clip before the key statement.",
                icon: "text.bubble"
            )

            TextField("Voice brief summary (optional Prakeet note transcription)", text: $voiceBriefSummary)
                .textFieldStyle(.roundedBorder)
                .help("Use this for a typed version of what a voice note says until direct Prakeet capture is wired in.")

            Stepper(value: $workflowMaxMoments, in: 3...12) {
                HStack {
                    Text("Draft moments")
                        .saneReadableLabel()
                    Spacer()
                    Text("\(workflowMaxMoments)")
                        .saneReadableMeta(monospaced: true)
                }
            }
            .help("Controls how many draft cards SaneVideo tries to pull from the transcript.")
        }
    }

    private var commentarySection: some View {
        section(
            "Commentary Draft",
            subtitle: "Review concept cards first, then build the reel. Use the raw cue draft only when you need manual control."
        ) {
            HelperText(
                text: "This is the first slice of the workflow system: transcript-grounded concept cards that stay editable before export.",
                icon: "quote.bubble"
            )

            HStack(spacing: 12) {
                Button(isGeneratingCommentaryPlan ? "Generating Draft..." : "Generate Draft From Transcript") {
                    Task { await generateCommentaryPlan() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingCommentaryPlan)
                .help("Uses the current brief plus local transcript captions to draft concept cards.")

                Button("Use Cue Draft as Draft") {
                    importCueDraftIntoPlan()
                }
                .buttonStyle(.bordered)
                .help("Parses the raw cue draft below and turns it into editable concept cards.")

                Button("Clear Draft") {
                    commentaryPlanItems = []
                    commentaryLines = ""
                }
                .buttonStyle(.bordered)
                .help("Clears the concept-card draft and the raw cue text.")
            }

            if !commentaryPlanItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(commentaryPlanItems.indices), id: \.self) { index in
                        commentaryPlanCard(at: index)
                    }
                }
            } else {
                HelperText(
                    text: "No draft cards yet. Generate from the transcript or import raw cue lines.",
                    icon: "rectangle.stack.badge.plus"
                )
            }

            DisclosureGroup(
                isExpanded: $showAdvancedCueDraft,
                content: {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $commentaryLines)
                            .font(Theme.Typography.metaMonospaced)
                            .frame(minHeight: 140)
                            .padding(8)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Theme.Colors.cardBackground.opacity(0.92))
                            .sanePanel(radius: 12, accent: Theme.Colors.accentSoft)

                        HelperText(
                            text: "Format: `mm:ss-mm:ss | Concept | Point | Verse refs`",
                            icon: "sparkles.rectangle.stack"
                        )
                    }
                },
                label: {
                    Text("Advanced Cue Draft")
                        .saneReadableLabel()
                }
            )

            HStack(spacing: 12) {
                Button("Clear Commentary Cues") {
                    commentaryPlanItems = []
                    commentaryLines = ""
                }
                .buttonStyle(.bordered)
                .help("Clears the current commentary cue draft for this project.")

                Button("Build Commentary Reel") {
                    saveChanges(dismissAfter: false)
                    if appState.buildCommentaryReel() {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Creates a new project that keeps only these ranges, in this order, with verse text added at the start of each segment.")
            }
        }
    }

    @ViewBuilder
    private func commentaryPlanCard(at index: Int) -> some View {
        if commentaryPlanItems.indices.contains(index) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Draft \(index + 1)")
                            .saneReadableLabel()
                        Text(commentaryPlanItems[index].sourceTimestampRange)
                            .saneReadableMeta(monospaced: true)
                    }
                    Spacer()
                    Text("\(Int((commentaryPlanItems[index].confidence * 100).rounded()))%")
                        .saneReadableMeta(monospaced: true)
                }

                TextField("Concept", text: $commentaryPlanItems[index].concept)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: commentaryPlanItems[index].concept) { _, _ in
                        syncCueDraftFromPlan()
                    }

                TextField("Claim", text: $commentaryPlanItems[index].claim, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .onChange(of: commentaryPlanItems[index].claim) { _, _ in
                        syncCueDraftFromPlan()
                    }

                TextField("Supporting refs", text: $commentaryPlanItems[index].supportingReferences)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: commentaryPlanItems[index].supportingReferences) { _, _ in
                        syncCueDraftFromPlan()
                    }

                if !commentaryPlanItems[index].sourceExcerpt.isEmpty {
                    Text(commentaryPlanItems[index].sourceExcerpt)
                        .saneReadableSupportText()
                        .lineLimit(3)
                }

                HStack(spacing: 10) {
                    Button("Up") { movePlanItem(from: index, offset: -1) }
                        .buttonStyle(.bordered)
                        .disabled(index == 0)

                    Button("Down") { movePlanItem(from: index, offset: 1) }
                        .buttonStyle(.bordered)
                        .disabled(index == commentaryPlanItems.count - 1)

                    Spacer()

                    Button("Delete") {
                        commentaryPlanItems.remove(at: index)
                        syncCueDraftFromPlan()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .sanePanel(radius: 14, accent: Theme.Colors.accentSoft)
        }
    }

    private var demoPackSection: some View {
        section("Demo Pack", subtitle: "Everything exports as local files. Nothing is hosted for the user.") {
            FeatureCallout(
                title: "File bundle, not hosted pages",
                message: "Turn on only the assets you actually want. Every item is written as a plain file you can upload anywhere yourself.",
                icon: "shippingbox.fill"
            )

            LabeledToggleRow(
                title: "Landscape master video",
                message: "Creates the main 16:9 export. Leave this on for normal product demos.",
                isOn: $includeLandscapeVideo
            )
            LabeledToggleRow(
                title: "Vertical variant",
                message: "Creates a 9:16 version for launch clips, reels, and mobile-first posts.",
                isOn: $includeVerticalVariant
            )
            LabeledToggleRow(
                title: "Square teaser variant",
                message: "Creates a square cut for changelog snippets, social cards, or compact embeds.",
                isOn: $includeSquareVariant
            )
            LabeledToggleRow(
                title: "Thumbnail PNG",
                message: "Exports a reusable thumbnail image you can drop into docs, launch posts, or upload forms.",
                isOn: $includeThumbnail
            )
            LabeledToggleRow(
                title: "Transcript text",
                message: "Writes a plain text transcript that is easy to edit, paste, or search.",
                isOn: $includeTranscriptText
            )
            LabeledToggleRow(
                title: "Transcript PDF",
                message: "Writes a styled PDF transcript when you need a shareable document version.",
                isOn: $includeTranscriptPDF
            )
            LabeledToggleRow(
                title: "Speaker notes markdown",
                message: "Exports your script as Markdown so the notes travel with the bundle.",
                isOn: $includeSpeakerNotes
            )
            LabeledToggleRow(
                title: "Chapter markdown + JSON",
                message: "Exports human-readable and machine-readable chapter files for reuse in docs or automations.",
                isOn: $includeChapters
            )
            LabeledToggleRow(
                title: "Publish metadata files",
                message: "Exports title, subtitle, description, and call-to-action text alongside the video files.",
                isOn: $includePublishMetadata
            )
        }
    }

    private func section<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .saneReadableSectionTitle()
                Text(subtitle)
                    .saneReadableSupportText()
            }

            content()
        }
        .padding(18)
        .sanePanel(radius: 16, accent: Theme.Colors.accentSoft)
    }

    private func sliderField(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .saneReadableLabel()
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .saneReadableMeta(monospaced: true)
            }

            Slider(value: value, in: range, step: step)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadProject() {
        guard let project = appState.currentProject else { return }
        guard loadedProjectID != project.id else { return }

        loadedProjectID = project.id
        presentationPreset = project.presentationPreset

        speakerNotesText = project.speakerNotes.text
        speakerNotesFontSize = project.speakerNotes.fontSize
        speakerNotesOpacity = project.speakerNotes.opacity
        speakerNotesWidth = project.speakerNotes.widthFraction
        speakerNotesScrollSpeed = project.speakerNotes.scrollSpeed
        speakerNotesMirrored = project.speakerNotes.isMirrored
        teleprompterVisible = project.speakerNotes.isVisible

        publishTitle = project.publishMetadata.title
        publishSubtitle = project.publishMetadata.subtitle
        publishDescription = project.publishMetadata.description
        publishCTA = project.publishMetadata.callToAction

        workflowPack = project.workflowBrief.workflow
        workflowInstructions = project.workflowBrief.instructions
        voiceBriefSummary = project.workflowBrief.voiceBriefSummary
        workflowMaxMoments = min(max(project.workflowBrief.maxMoments, 3), 12)

        chapterLines = serializedChapterLines(project.chapterMarkers)
        commentaryPlanItems = project.commentaryPlanItems.isEmpty
            ? CommentaryPlanItem.fromMarkers(project.commentaryMarkers)
            : CommentaryPlanItem.ordered(project.commentaryPlanItems)
        let markerSource = commentaryPlanItems.isEmpty
            ? project.commentaryMarkers
            : commentaryPlanItems.map(\.commentaryMarker)
        commentaryLines = CommentaryMarker.serializeLines(markerSource)
        applyDemoPackSettings(project.demoPackSettings)
    }

    private func saveChanges(dismissAfter: Bool) {
        let notes = SpeakerNotes(
            text: speakerNotesText,
            fontSize: speakerNotesFontSize,
            opacity: speakerNotesOpacity,
            widthFraction: speakerNotesWidth,
            scrollSpeed: speakerNotesScrollSpeed,
            isMirrored: speakerNotesMirrored,
            isVisible: teleprompterVisible
        )

        let publishMetadata = PublishMetadata(
            title: publishTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: publishSubtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            description: publishDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            callToAction: publishCTA.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let demoPackSettings = DemoPackSettings(
            includeLandscapeVideo: includeLandscapeVideo,
            includeVerticalVariant: includeVerticalVariant,
            includeSquareVariant: includeSquareVariant,
            includeThumbnail: includeThumbnail,
            includeTranscriptText: includeTranscriptText,
            includeTranscriptPDF: includeTranscriptPDF,
            includeSpeakerNotes: includeSpeakerNotes,
            includeChapters: includeChapters,
            includePublishMetadata: includePublishMetadata
        )

        let workflowBrief = WorkflowBrief(
            workflow: workflowPack,
            instructions: workflowInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            voiceBriefSummary: voiceBriefSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            maxMoments: workflowMaxMoments
        )

        let normalizedPlanItems = normalizedCommentaryPlanItems()
        let savedMarkers: [CommentaryMarker]
        let savedPlanItems: [CommentaryPlanItem]

        if normalizedPlanItems.isEmpty {
            savedMarkers = CommentaryMarker.ordered(CommentaryMarker.parseLines(commentaryLines))
            savedPlanItems = CommentaryPlanItem.fromMarkers(savedMarkers)
        } else {
            savedPlanItems = normalizedPlanItems
            savedMarkers = savedPlanItems.map(\.commentaryMarker)
        }

        commentaryPlanItems = savedPlanItems
        commentaryLines = CommentaryMarker.serializeLines(savedMarkers)

        appState.projectState.updatePresentationPreset(presentationPreset)
        appState.projectState.updateChapterMarkers(parseChapterLines(chapterLines))
        appState.projectState.updateWorkflowBrief(workflowBrief)
        appState.projectState.updateCommentaryPlanItems(savedPlanItems)
        appState.projectState.updateCommentaryMarkers(savedMarkers)
        appState.projectState.updateDemoPackSettings(demoPackSettings)
        appState.projectState.updatePublishMetadata(publishMetadata)
        appState.setTeleprompterVisible(teleprompterVisible, notesOverride: notes)

        ServiceContainer.shared.toastManager.show("Saved demo studio settings", type: .success)

        if dismissAfter && (!teleprompterVisible || notes.hasContent) {
            dismiss()
        }
    }

    private func applyDemoPackSettings(_ settings: DemoPackSettings) {
        includeLandscapeVideo = settings.includeLandscapeVideo
        includeVerticalVariant = settings.includeVerticalVariant
        includeSquareVariant = settings.includeSquareVariant
        includeThumbnail = settings.includeThumbnail
        includeTranscriptText = settings.includeTranscriptText
        includeTranscriptPDF = settings.includeTranscriptPDF
        includeSpeakerNotes = settings.includeSpeakerNotes
        includeChapters = settings.includeChapters
        includePublishMetadata = settings.includePublishMetadata
    }

    private func normalizedCommentaryPlanItems() -> [CommentaryPlanItem] {
        CommentaryPlanItem.ordered(
            commentaryPlanItems.enumerated().compactMap { index, item in
                let concept = item.trimmedConcept.isEmpty ? "Commentary" : item.trimmedConcept
                let claim = item.trimmedClaim
                let references = item.supportingReferences.trimmingCharacters(in: .whitespacesAndNewlines)
                let excerpt = item.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
                let start = max(0, item.startTime)
                let end = item.endTime

                guard !claim.isEmpty, end > start else { return nil }

                return CommentaryPlanItem(
                    id: item.id,
                    concept: concept,
                    claim: claim,
                    supportingReferences: references,
                    sourceExcerpt: excerpt,
                    startTime: start,
                    endTime: end,
                    confidence: min(max(item.confidence, 0), 1),
                    sortOrder: index
                )
            }
        )
    }

    private func syncCueDraftFromPlan() {
        commentaryLines = CommentaryMarker.serializeLines(
            normalizedCommentaryPlanItems().map(\.commentaryMarker)
        )
    }

    private func importCueDraftIntoPlan() {
        let markers = CommentaryMarker.parseLines(commentaryLines)
        guard !markers.isEmpty else {
            ServiceContainer.shared.toastManager.show("No cue lines could be parsed", type: .error)
            return
        }

        commentaryPlanItems = CommentaryPlanItem.fromMarkers(markers)
        syncCueDraftFromPlan()
        ServiceContainer.shared.toastManager.show("Imported cue draft into concept cards", type: .success)
    }

    private func movePlanItem(from index: Int, offset: Int) {
        let newIndex = index + offset
        guard commentaryPlanItems.indices.contains(index),
              commentaryPlanItems.indices.contains(newIndex)
        else {
            return
        }

        var updatedItems = commentaryPlanItems
        let movedItem = updatedItems.remove(at: index)
        updatedItems.insert(movedItem, at: newIndex)
        commentaryPlanItems = updatedItems.enumerated().map { position, item in
            var reorderedItem = item
            reorderedItem.sortOrder = position
            return reorderedItem
        }
        syncCueDraftFromPlan()
    }

    private func availableTranscriptCaptions() -> [Caption] {
        guard let project = appState.currentProject else { return [] }

        return project.timeline.tracks
            .filter { $0.type == .video }
            .flatMap(\.clips)
            .sorted { $0.startTime < $1.startTime }
            .first(where: { !$0.captions.isEmpty })?
            .captions
            .sorted { $0.startTime < $1.startTime } ?? []
    }

    private func generateCommentaryPlan() async {
        let captions = availableTranscriptCaptions()
        guard !captions.isEmpty else {
            ServiceContainer.shared.toastManager.show("Add transcript captions before generating a draft", type: .error)
            return
        }

        isGeneratingCommentaryPlan = true
        defer { isGeneratingCommentaryPlan = false }

        let brief = WorkflowBrief(
            workflow: workflowPack,
            instructions: workflowInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            voiceBriefSummary: voiceBriefSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            maxMoments: workflowMaxMoments
        )
        let existingPlanMarkers = normalizedCommentaryPlanItems().map(\.commentaryMarker)
        let seedMarkers = existingPlanMarkers.isEmpty
            ? CommentaryMarker.parseLines(commentaryLines)
            : existingPlanMarkers

        let generatedItems = await ServiceContainer.shared.aiService.generateCommentaryPlan(
            captions: captions,
            brief: brief,
            existingMarkers: seedMarkers
        )
        let normalizedItems = CommentaryPlanItem.ordered(
            generatedItems.enumerated().map { index, item in
                var normalizedItem = item
                normalizedItem.sortOrder = index
                return normalizedItem
            }
        )

        commentaryPlanItems = normalizedItems
        syncCueDraftFromPlan()

        let message = normalizedItems.isEmpty
            ? "No draft moments were found in the transcript"
            : "Generated \(normalizedItems.count) draft \(normalizedItems.count == 1 ? "card" : "cards")"
        let toastType: ToastManager.AlertType = normalizedItems.isEmpty ? .error : .success
        ServiceContainer.shared.toastManager.show(message, type: toastType)
    }

    private func clipBoundaryChapterLines() -> String {
        guard let project = appState.currentProject else { return "" }

        let clips = project.timeline.tracks
            .flatMap(\.clips)
            .sorted { $0.startTime < $1.startTime }

        return clips.enumerated().map { index, clip in
            let title = clip.url.deletingPathExtension().lastPathComponent.isEmpty
                ? "Chapter \(index + 1)"
                : clip.url.deletingPathExtension().lastPathComponent
            return "\(timestampString(clip.startTime.seconds)) \(title)"
        }.joined(separator: "\n")
    }

    private func serializedChapterLines(_ chapters: [ChapterMarker]) -> String {
        chapters
            .sorted { $0.timestamp < $1.timestamp }
            .map { "\(timestampString($0.timestamp)) \($0.title)" }
            .joined(separator: "\n")
    }

    private func parseChapterLines(_ raw: String) -> [ChapterMarker] {
        raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard let rawTime = parts.first,
                      let timestamp = parseTimestamp(String(rawTime))
                else {
                    return nil
                }

                let title = parts.count > 1 ? String(parts[1]) : "Chapter"
                return ChapterMarker(title: title, timestamp: timestamp)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func parseTimestamp(_ raw: String) -> Double? {
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

    private func timestampString(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    DemoStudioSheet()
        .environment(ServiceContainer.shared.appState)
}
