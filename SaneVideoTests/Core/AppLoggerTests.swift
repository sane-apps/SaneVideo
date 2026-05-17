import Testing

@testable import SaneVideo

@Suite("App Logger Tests")
struct AppLoggerTests {
    @Test("Log sanitizer removes absolute user paths")
    func logSanitizerRemovesAbsoluteUserPaths() {
        let sanitized = AppLogger.sanitizeForLog(
            "Export success: /Users/alice/Movies/SaneVideo/Projects/customer-demo.mp4"
        )

        #expect(!sanitized.contains("/Users/alice"))
        #expect(sanitized.contains("/Users/<user>") || sanitized.contains("~/"))
        #expect(sanitized.contains("customer-demo.mp4"))
    }

    @MainActor
    @Test("Diagnostics log stays out of Documents")
    func diagnosticsLogStaysOutOfDocuments() {
        let url = LogManager.diagnosticLogURL()

        #expect(url?.lastPathComponent == LogManager.diagnosticLogFileName)
        #expect(url?.path.contains("/Application Support/SaneVideo/Logs/") == true)
        #expect(url?.path.contains("/Documents/") == false)
    }
}
