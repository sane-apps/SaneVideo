import AppKit
import Foundation

class ShareLinkService {

    init() {}

    /// Share a file URL using the system sharing service (Messages, Mail, AirDrop, etc.)
    /// - Parameters:
    ///   - sourceView: The NSView to anchor the share sheet to
    @MainActor
    func shareFile(at url: URL, from sourceView: NSView?) {
        let sharingPicker = NSSharingServicePicker(items: [url])

        let viewToUse = sourceView ?? NSApp.windows.first(where: { $0.isKeyWindow })?.contentView

        if let view = viewToUse {
            sharingPicker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else {
            AppLogger.general.warning("No view to anchor share sheet")
        }
    }

    func createPublicLink(for _: URL) async throws -> URL {
        throw AppError.recordingEngineError("Public link sharing requires a backend service. Use the share button for Messages, Mail, AirDrop, etc.")
    }
}
