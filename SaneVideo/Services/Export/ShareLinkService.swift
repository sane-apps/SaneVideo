import AppKit
import Foundation

/// Service to handle sharing of video files via the system share sheet
class ShareLinkService {

    init() {}

    /// Share a file URL using the system sharing service (Messages, Mail, AirDrop, etc.)
    /// - Parameters:
    ///   - url: The file URL to share
    ///   - sourceView: The NSView to anchor the share sheet to
    @MainActor
    func shareFile(at url: URL, from sourceView: NSView?) {
        let sharingPicker = NSSharingServicePicker(items: [url])

        // Find a valid view if none provided (fallback)
        let viewToUse = sourceView ?? NSApp.windows.first(where: { $0.isKeyWindow })?.contentView

        if let view = viewToUse {
            sharingPicker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else {
            // Fallback: This shouldn't happen in a proper UI flow
            AppLogger.general.warning("No view to anchor share sheet")
        }
    }

    // Future feature: Create public shareable link (requires backend service)
    // This would upload the video to a cloud service and return a shareable URL
    // For now, users can share via the system share sheet (Messages, Mail, AirDrop, etc.)
    func createPublicLink(for _: URL) async throws -> URL {
        // FUTURE: Implement backend upload logic here
        // This would require:
        // 1. Upload service (AWS S3, Cloudflare R2, etc.)
        // 2. CDN for delivery
        // 3. Link generation service
        // For MVP, system share sheet is sufficient
        throw AppError.recordingEngineError("Public link sharing requires a backend service. Use the share button for Messages, Mail, AirDrop, etc.")
    }
}
