// Permission errors must give the user something to act on: the error panel shows
// their title, message and recovery steps.
// Export failure/cancel cleanup from the same audit is covered with real exports in
// ExportEdgeCaseIntegrationTests.

import Foundation
@testable import SaneVideo
import Testing

@Suite("Permission Error Copy")
struct SessionAuditRegressionTests {
    @Test("Permission errors carry a title, a message and recovery steps")
    func permissionErrorsAreActionable() {
        let errors: [AppError] = [
            .cameraPermissionDenied,
            .cameraPermissionRestricted,
            .microphonePermissionDenied,
            .microphonePermissionRestricted
        ]

        for error in errors {
            #expect(!error.userFacingTitle.isEmpty, "\(error) has no title")
            #expect(!error.userFacingMessage.isEmpty, "\(error) has no message")
            #expect(!error.recoverySuggestions.isEmpty, "\(error) has no recovery steps")
        }
    }
}
