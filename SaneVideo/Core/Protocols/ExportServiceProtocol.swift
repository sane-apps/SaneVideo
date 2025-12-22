//
//  ExportServiceProtocol.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation

@MainActor
protocol ExportServiceProtocol {
    var progress: Double { get }
    var isExporting: Bool { get }

    func export(
        project: VideoProject,
        settings: SaneExportSettings,
        outputURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    func cancelExport()
}
