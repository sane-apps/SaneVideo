//
//  PerformanceMetricsService.swift
//  SaneVideo
//
//  Tracks performance metrics for better debugging and user insights
//

import Foundation

/// Tracks performance metrics for operations
@MainActor
@Observable
class PerformanceMetricsService {

    struct OperationMetrics: Identifiable {
        let id = UUID()
        let name: String
        let duration: TimeInterval
        let timestamp: Date
        let metadata: [String: String]
    }

    private(set) var recentOperations: [OperationMetrics] = []
    private let maxStoredOperations = 100

    // Statistics
    private(set) var averageExportTime: TimeInterval = 0
    private(set) var averageMagicFixTime: TimeInterval = 0
    private(set) var fastestExportTime: TimeInterval = .greatestFiniteMagnitude
    private(set) var slowestExportTime: TimeInterval = 0

    init() {}

    /// Record an operation's performance
    func recordOperation(name: String, duration: TimeInterval, metadata: [String: String] = [:]) {
        let metrics = OperationMetrics(
            name: name,
            duration: duration,
            timestamp: Date(),
            metadata: metadata
        )

        recentOperations.append(metrics)
        if recentOperations.count > maxStoredOperations {
            recentOperations.removeFirst()
        }

        // Update statistics
        updateStatistics()

        // Log for debugging
        AppLogger.general.info("📊 Performance: \(name) took \(String(format: "%.2f", duration))s")
    }

    private func updateStatistics() {
        let exports = recentOperations.filter { $0.name.contains("Export") }
        let magicFixes = recentOperations.filter { $0.name.contains("Magic Fix") }

        if !exports.isEmpty {
            averageExportTime = exports.map { $0.duration }.reduce(0, +) / Double(exports.count)
            fastestExportTime = exports.map { $0.duration }.min() ?? .greatestFiniteMagnitude
            slowestExportTime = exports.map { $0.duration }.max() ?? 0
        }

        if !magicFixes.isEmpty {
            averageMagicFixTime = magicFixes.map { $0.duration }.reduce(0, +) / Double(magicFixes.count)
        }
    }

    /// Get performance insights for user
    func getPerformanceInsights() -> [String] {
        var insights: [String] = []

        if averageExportTime > 0 {
            insights.append("Average export time: \(formatDuration(averageExportTime))")
        }

        if averageMagicFixTime > 0 {
            insights.append("Average Magic Fix time: \(formatDuration(averageMagicFixTime))")
        }

        if fastestExportTime < .greatestFiniteMagnitude {
            insights.append("Fastest export: \(formatDuration(fastestExportTime))")
        }

        return insights
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        TimeUtils.formatInsightDuration(duration)
    }

    func clearMetrics() {
        recentOperations.removeAll()
        averageExportTime = 0
        averageMagicFixTime = 0
        fastestExportTime = .greatestFiniteMagnitude
        slowestExportTime = 0
    }
}
