import Foundation

enum LocalSaneAIWorkflowRunner {
    private struct RequestPayload: Encodable {
        let model: String
        let adapterPath: String
        let systemPrompt: String
        let prompt: String
        let maxTokens: Int
    }

    private struct WorkflowResponse: Decodable {
        let workflow: String
        let summary: String
        let items: [WorkflowItem]
    }

    private struct WorkflowItem: Decodable {
        let concept: String
        let claim: String
        let supportingReferences: String?
        let sourceExcerpt: String
        let startTime: Double
        let endTime: Double
        let confidence: Double
    }

    private static let enableEnv = "SANEVIDEO_USE_LOCAL_SANEAI"
    private static let pythonEnv = "SANEVIDEO_LOCAL_SANEAI_PYTHON"
    private static let maxTokensEnv = "SANEVIDEO_LOCAL_SANEAI_MAX_TOKENS"
    private static let defaultPython = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("SaneApps/SaneAI/.venv-local/bin/python3").path

    static var shouldUseLocalModel: Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[enableEnv]?.lowercased(),
              ["1", "true", "yes"].contains(rawValue) else {
            return false
        }

        return FileManager.default.isExecutableFile(atPath: pythonPath.path)
            && FileManager.default.fileExists(atPath: helperScriptURL.path)
            && FileManager.default.fileExists(atPath: adapterConfigURL.path)
            && FileManager.default.fileExists(atPath: systemPromptURL.path)
    }

    static func generatePlan(
        captions: [Caption],
        brief: WorkflowBrief,
        existingMarkers: [CommentaryMarker]
    ) async throws -> [CommentaryPlanItem] {
        let transcript = transcriptString(from: captions)
        guard !transcript.isEmpty else { return [] }

        let adapterConfigData = try Data(contentsOf: adapterConfigURL)
        let adapterConfig = try JSONDecoder().decode(AdapterConfig.self, from: adapterConfigData)
        let systemPrompt = try String(contentsOf: systemPromptURL, encoding: .utf8)
        let payload = RequestPayload(
            model: adapterConfig.model,
            adapterPath: productionAdapterURL.path,
            systemPrompt: systemPrompt,
            prompt: prompt(for: brief, transcript: transcript, existingMarkers: existingMarkers),
            maxTokens: maxTokens
        )

        let inputData = try JSONEncoder().encode(payload)
        let outputData = try await runHelper(with: inputData)
        return try parsePlan(from: outputData)
    }

    static func parsePlan(from data: Data) throws -> [CommentaryPlanItem] {
        let responseData = try extractJSONObject(from: data)
        let response = try JSONDecoder().decode(WorkflowResponse.self, from: responseData)
        return CommentaryPlanItem.ordered(
            response.items.enumerated().map { index, item in
                CommentaryPlanItem(
                    concept: item.concept.trimmingCharacters(in: .whitespacesAndNewlines),
                    claim: item.claim.trimmingCharacters(in: .whitespacesAndNewlines),
                    supportingReferences: item.supportingReferences?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    sourceExcerpt: item.sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: max(0, item.startTime),
                    endTime: max(item.startTime, item.endTime),
                    confidence: item.confidence,
                    sortOrder: index
                )
            }
        )
    }

    private static func runHelper(with inputData: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = pythonPath
            process.arguments = [helperScriptURL.path]

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: outputData)
                    return
                }

                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = errorText?.isEmpty == false
                    ? errorText!
                    : "Local workflow helper exited with status \(process.terminationStatus)."
                continuation.resume(throwing: AIError.apiError(message))
            }

            do {
                try process.run()
                stdinPipe.fileHandleForWriting.write(inputData)
                try? stdinPipe.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: AIError.networkError(error))
            }
        }
    }

    private static func prompt(
        for brief: WorkflowBrief,
        transcript: String,
        existingMarkers: [CommentaryMarker]
    ) -> String {
        let instructions = brief.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceBrief = brief.voiceBriefSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let markerHints = CommentaryMarker.ordered(existingMarkers)
            .prefix(3)
            .map { marker in
                "\(marker.sourceTimestampRange) | \(marker.trimmedConcept ?? "Commentary") | \(marker.title)"
            }
            .joined(separator: "\n")

        var lines = [
            "Build a SaneVideo workflow draft.",
            "Return only valid JSON with workflow, summary, and items.",
            "Workflow: \(brief.workflow.rawValue)",
            "Max moments: \(max(brief.maxMoments, 1))"
        ]

        if !instructions.isEmpty {
            lines.append("Instructions: \(instructions)")
        }

        if !voiceBrief.isEmpty {
            lines.append("Voice brief: \(voiceBrief)")
        }

        if !markerHints.isEmpty {
            lines.append("Existing marker hints:")
            lines.append(markerHints)
        }

        lines.append("Transcript:")
        lines.append(transcript)
        return lines.joined(separator: "\n")
    }

    private static func transcriptString(from captions: [Caption]) -> String {
        captions
            .sorted { $0.startTime < $1.startTime }
            .map { caption in
                "[\(timestampString(for: caption.startTime.seconds))] \(caption.displayText.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            .filter { !$0.hasSuffix("] ") }
            .joined(separator: "\n")
    }

    private static func timestampString(for seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func extractJSONObject(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AIError.invalidResponse
        }

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            throw AIError.invalidResponse
        }

        return Data(text[start...end].utf8)
    }

    private static var maxTokens: Int {
        if let rawValue = ProcessInfo.processInfo.environment[maxTokensEnv],
           let parsed = Int(rawValue),
           parsed > 0 {
            return parsed
        }
        return 384
    }

    private static var pythonPath: URL {
        if let override = ProcessInfo.processInfo.environment[pythonEnv], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: defaultPython)
    }

    private static var helperScriptURL: URL {
        repoRootURL
            .appendingPathComponent("scripts")
            .appendingPathComponent("local_saneai_workflow.py")
    }

    private static var productionAdapterURL: URL {
        saneAIRootURL
            .appendingPathComponent("models")
            .appendingPathComponent("production_adapter")
    }

    private static var adapterConfigURL: URL {
        productionAdapterURL.appendingPathComponent("adapter_config.json")
    }

    private static var systemPromptURL: URL {
        saneAIRootURL
            .appendingPathComponent("training_data")
            .appendingPathComponent("system_prompt.txt")
    }

    private static var saneAIRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("SaneApps")
            .appendingPathComponent("SaneAI")
    }

    private static var repoRootURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private struct AdapterConfig: Decodable {
        let model: String
    }
}
