//
//  ExportEngine.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import CoreMedia

@MainActor
class ExportEngine: ExportServiceProtocol {

    // MARK: - Properties

    private var exportSession: AVAssetExportSession?
    private let compositor = ExportCompositor()
    private let progressTracker = ExportProgressTracker()
    private var exportCancellables = Set<AnyCancellable>()
    private var permanentCancellables = Set<AnyCancellable>()

    // MARK: - Public State

    private(set) var isExporting = false
    private(set) var progress: Double = 0

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    private func setupBindings() {
        progressTracker.progressSubject
            .sink { [weak self] progress in
                Task { @MainActor in
                    self?.progress = progress
                }
            }
            .store(in: &permanentCancellables)
    }

    // MARK: - Export

    nonisolated func export(
        project: VideoProject,
        settings: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        Task { @MainActor in
            await self.performExport(
                project: project,
                settings: settings,
                outputURL: outputURL,
                progressHandler: progressHandler,
                completion: completion
            )
        }
    }

    private func performExport(
        project: VideoProject,
        settings: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<URL, Error>) -> Void
    ) async {
        guard !isExporting else {
            completion(.failure(ExportError.alreadyExporting))
            return
        }

        isExporting = true
        progress = 0

        do {
            // Create composition (Heavy work) - now async
            let compositionResult = try await compositor.createComposition(from: project)
            let composition = compositionResult.composition
            let baseVideoComposition = compositionResult.videoComposition
            let audioMix = compositionResult.audioMix

            // Setup export session
            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHEVCHighestQuality
            ) else {
                throw ExportError.failedToCreateSession
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = AVFileType.mp4
            exportSession.audioMix = audioMix

            // Configure video settings
            exportSession.videoComposition = try await compositor.createVideoComposition(
                for: composition,
                baseVideoComposition: baseVideoComposition,
                settings: settings
            )

            // Start export
            self.exportSession = exportSession
            progressTracker.startMonitoring(session: exportSession)

            // Observe progress for the handler
            progressTracker.progressSubject
                .sink { progress in
                    progressHandler(progress)
                }
                .store(in: &exportCancellables)

            if #available(macOS 15.0, *) {
                try await exportSession.export(to: outputURL, as: .mp4)
                await handleExportCompletion(outputURL: outputURL, error: nil, completion: completion)
            } else {
                await exportSession.export()
                // Legacy check
                let error = exportSession.error
                if exportSession.status == .completed {
                    await handleExportCompletion(outputURL: outputURL, error: nil, completion: completion)
                } else {
                    await handleExportCompletion(outputURL: outputURL, error: error ?? ExportError.unknown, completion: completion)
                }
            }
        } catch {
            isExporting = false
            progressTracker.stopMonitoring()
            exportCancellables.removeAll()
            completion(.failure(error))
            exportSession = nil
        }
    }

    private func handleExportCompletion(outputURL: URL, error: Error?, completion: @escaping (Result<URL, Error>) -> Void) async {
        isExporting = false
        progressTracker.stopMonitoring()
        exportCancellables.removeAll()

        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(outputURL))
        }

        exportSession = nil
    }

    func cancelExport() {
        exportSession?.cancelExport()
        isExporting = false
        Task { @MainActor in
            progressTracker.stopMonitoring()
        }
        exportSession = nil
        exportCancellables.removeAll()
    }
}
