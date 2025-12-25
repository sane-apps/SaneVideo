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
        // CRITICAL FIX: Store outputURL for cleanup on error
        let exportOutputURL = outputURL
        
        self.exportSession = exportSession
        progressTracker.startMonitoring(session: exportSession)

        // Observe progress for the handler
        progressTracker.progressSubject
            .sink { progress in
                progressHandler(progress)
            }
            .store(in: &exportCancellables)

        // CRITICAL FIX: Retry export operation for transient failures
        // Note: AVAssetExportSession is not Sendable, so we can't use retryOperation directly
        // Instead, we'll manually retry once for recoverable errors
        var lastError: Error?
        var attempt = 0
        let maxAttempts = 2
        
        while attempt < maxAttempts {
            attempt += 1
            do {
                if #available(macOS 15.0, *) {
                    AppLogger.project.info("🚀 Using modern async export pattern (macOS 15+)")
                    try await exportSession.export(to: outputURL, as: .mp4)
                } else {
                    AppLogger.project.info("⏳ Using legacy export pattern")
                    await exportSession.export()
                    if exportSession.status != .completed {
                        throw exportSession.error ?? ExportError.unknown
                    }
                }
                // Success - exit retry loop
                return try await handleExportCompletion(outputURL: outputURL, error: nil)
            } catch {
                lastError = error
                
                // Check if error is recoverable and we haven't exhausted attempts
                if isRecoverableError(error) && attempt < maxAttempts {
                    AppLogger.export.warning("⚠️ Export failed (attempt \(attempt)/\(maxAttempts)), retrying: \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    continue // Retry
                } else {
                    // Non-recoverable error or last attempt failed
                    break // Exit retry loop
                }
            }
        }
        
        // All attempts failed - clean up and throw error
        if let error = lastError {
            AppLogger.export.error("❌ Export failed after \(maxAttempts) attempts: \(error.localizedDescription)")
            
            // CRITICAL FIX: Clean up partial file on failure
            if FileManager.default.fileExists(atPath: exportOutputURL.path) {
                do {
                    try FileManager.default.removeItem(at: exportOutputURL)
                    AppLogger.export.info("Cleaned up partial export file after failure: \(exportOutputURL.lastPathComponent)")
                } catch {
                    AppLogger.export.warning("Failed to clean up partial file: \(error.localizedDescription)")
                }
            }
            
            self.exportSession = nil
            isExporting = false
            progressTracker.stopMonitoring()
            exportCancellables.removeAll()
            throw error
        } else {
            // This should never happen, but handle gracefully
            throw ExportError.unknown
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
            // CRITICAL FIX: Clean up partial file on error
            if FileManager.default.fileExists(atPath: outputURL.path) {
                do {
                    try FileManager.default.removeItem(at: outputURL)
                    AppLogger.export.info("Cleaned up partial export file after error: \(outputURL.lastPathComponent)")
                } catch {
                    AppLogger.export.warning("Failed to clean up partial file: \(error.localizedDescription)")
                }
            }
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
