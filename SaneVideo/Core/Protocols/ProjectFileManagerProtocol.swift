import AVFoundation
import Foundation

/// @mockable
protocol ProjectFileManagerProtocol: Sendable {
    func loadClip(from url: URL) async throws -> VideoClip

    nonisolated func createBookmark(for url: URL) throws -> Data

    /// Resolves a bookmark to a URL, returning (URL, isStale)
    func resolveBookmark(data: Data) throws -> (URL, Bool)

    func deleteFile(at url: URL) async throws

    /// Resolves bookmarks for all clips in a project
    /// Returns (updatedProject, needsSave)
    func hydrateProject(_ project: VideoProject) -> (VideoProject, Bool)

    func enterSecurityScope(for project: VideoProject) -> ProjectFileManager.SecurityScopeSession
}
