//
//  ProjectStoreProtocol.swift
//  SaneVideo
//
//  Protocol for project persistence abstraction

import Foundation

/// Protocol defining project storage operations
protocol ProjectStoreProtocol: AnyObject, Sendable {
    /// Load all saved projects
    /// - Returns: Array of video projects
    func loadProjects() async throws -> [VideoProject]

    /// Save a project
    /// - Parameter project: Project to save
    func saveProject(_ project: VideoProject) async throws

    /// Delete a project
    /// - Parameter project: Project to delete
    func deleteProject(_ project: VideoProject) async throws

    /// Get recent projects (sorted by modification date)
    /// - Parameter limit: Maximum number of projects to return
    /// - Returns: Recent projects
    func recentProjects(limit: Int) async throws -> [VideoProject]

    /// Get the file URL for a given project (if using file-based storage)
    /// - Parameter project: The project to locate
    /// - Returns: The file URL used for storage
    func fileURL(for project: VideoProject) -> URL
}
