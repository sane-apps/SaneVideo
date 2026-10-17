import Foundation

/// @mockable
protocol ProjectStoreProtocol: AnyObject, Sendable {
    func loadProjects() async throws -> [VideoProject]

    func saveProject(_ project: VideoProject) async throws

    func deleteProject(_ project: VideoProject) async throws

    /// Get recent projects (sorted by modification date)
    func recentProjects(limit: Int) async throws -> [VideoProject]

    /// Get the file URL for a given project (if using file-based storage)
    func fileURL(for project: VideoProject) -> URL
}
