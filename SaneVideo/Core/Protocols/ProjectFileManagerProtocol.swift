//
//  ProjectFileManagerProtocol.swift
//  SaneVideo
//
//  Protocol for project file management operations
//

import AVFoundation
import Foundation

/// @mockable
protocol ProjectFileManagerProtocol: Sendable {
    /// Load a video clip from a URL
    func loadClip(from url: URL) async throws -> VideoClip

    /// Creates a security-scoped bookmark for a URL
    nonisolated func createBookmark(for url: URL) throws -> Data

    /// Resolves a bookmark to a URL, returning (URL, isStale)
    func resolveBookmark(data: Data) throws -> (URL, Bool)

    /// Delete a file
    func deleteFile(at url: URL) async throws

    /// Resolves bookmarks for all clips in a project
    /// Returns (updatedProject, needsSave)
    func hydrateProject(_ project: VideoProject) -> (VideoProject, Bool)

    /// Enters security scope for all media in a project
    func enterSecurityScope(for project: VideoProject) -> ProjectFileManager.SecurityScopeSession
}
