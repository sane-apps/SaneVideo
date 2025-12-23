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
    
    // Performance tracking
    private var currentExportStartTime: Date?
    private var currentExportSettings: SaneExportSettings?

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
                    // Update speed tracker if we have file size info
                    // Note: AVAssetExportSession doesn't provide bytes processed directly
                    // We'll estimate based on progress
                }
            }
            .store(in: &permanentCancellables)
    }

    // MARK: - Export

    func export(
        project: VideoProject,
        settings: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        return try await self.performExport(
            project: project,
            settings: settings,
            outputURL: outputURL,
            progressHandler: progressHandler
        )
    }

    private func performExport(
        project: VideoProject,
        settings: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard !isExporting else {
            throw ExportError.alreadyExporting
        }

        isExporting = true
        progress = 0
        
        // Start performance tracking
        currentExportStartTime = Date()
        currentExportSettings = settings

        do {
            // Create composition (Heavy work) - now async
            // Note: Composition creation is usually reliable, retry only for transient failures
            let compositionResult = try await compositor.createComposition(from: project)
            let composition = compositionResult.composition
            let baseVideoComposition = compositionResult.videoComposition
            let audioMix = compositionResult.audioMix

            // Setup export session (with fallback if HEVC fails)
            var exportSession: AVAssetExportSession?
            
            // Try HEVC first
            exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHEVCHighestQuality)
            
            // Fallback to H.264 if HEVC unavailable
            if exportSession == nil {
                AppLogger.export.warning("⚠️ HEVC export session unavailable, trying H.264 fallback")
                exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            }
            
            guard let exportSession = exportSession else {
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

            // Start export with retry for transient failures
            return try await performExportWithSession(exportSession, outputURL: outputURL, progressHandler: progressHandler)
        } catch {
            isExporting = false
            progressTracker.stopMonitoring()
            exportCancellables.removeAll()
            exportSession = nil
            throw error
        }
    }
    
    private func performExportWithSession(
        _ exportSession: AVAssetExportSession,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        self.exportSession = exportSession
        progressTracker.startMonitoring(session: exportSession)

        // Observe progress for the handler
        progressTracker.progressSubject
            .sink { progress in
                progressHandler(progress)
            }
            .store(in: &exportCancellables)

        // Retry export operation for transient failures
        do {
            if #available(macOS 15.0, *) {
                AppLogger.project.info("🚀 Using modern async export pattern (macOS 15+)")
                try await exportSession.export(to: outputURL, as: .mp4)
                return try await handleExportCompletion(outputURL: outputURL, error: nil)
            } else {
                AppLogger.project.info("⏳ Using legacy export pattern")
                await exportSession.export()
                if exportSession.status == .completed {
                    return try await handleExportCompletion(outputURL: outputURL, error: nil)
                } else {
                    return try await handleExportCompletion(outputURL: outputURL, error: exportSession.error ?? ExportError.unknown)
                }
            }
        } catch {
            // If export fails, log and rethrow
            AppLogger.export.error("❌ Export failed: \(error.localizedDescription)")
            self.exportSession = nil
            isExporting = false
            progressTracker.stopMonitoring()
            exportCancellables.removeAll()
            throw error
        }
    }

    private func handleExportCompletion(outputURL: URL, error: Error?) async throws -> URL {
        isExporting = false
        progressTracker.stopMonitoring()
        exportCancellables.removeAll()

        exportSession = nil
        
        // Record performance metrics
        if let startTime = currentExportStartTime,
           let settings = currentExportSettings {
            let duration = Date().timeIntervalSince(startTime)
            let operationName = "Export_\(settings.resolution.rawValue)_\(settings.codec.rawValue)"
            let performanceMetrics = ServiceContainer.shared.performanceMetrics
            
            performanceMetrics.recordOperation(
                name: operationName,
                duration: duration,
                metadata: [
                    "resolution": settings.resolution.rawValue,
                    "codec": settings.codec.rawValue,
                    "success": error == nil ? "true" : "false"
                ]
            )
            
            // Clear tracking
            currentExportStartTime = nil
            currentExportSettings = nil
        }
        
        if let error = error {
            throw error
        } else {
            return outputURL
        }
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
