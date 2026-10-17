// Export error messages and resolution sizes.

import AVFoundation
@testable import SaneVideo
import Testing

@Suite("Export Types Tests")
struct ExportTypesTests {
    @Test("invalidProject shows the caller's message")
    func invalidProjectDescription() {
        let message = "Project has no video clips"
        #expect(ExportError.invalidProject(message).errorDescription == message)
    }

    @Test("insufficientDiskSpace names disk space and a byte unit")
    func insufficientDiskSpaceDescription() throws {
        let error = ExportError.insufficientDiskSpace(required: 1_000_000_000, available: 500_000_000)
        let description = try #require(error.errorDescription)

        #expect(description.lowercased().contains("disk"))
        #expect(description.contains("GB") || description.contains("MB"))
    }

    @Test("Every export error has its own message so users can tell failures apart")
    func allErrorsHaveUniqueDescriptions() {
        let errors: [ExportError] = [
            .alreadyExporting,
            .failedToCreateSession,
            .cancelled,
            .invalidProject("test"),
            .timeout,
            .insufficientDiskSpace(required: 1000, available: 500),
            .unknown
        ]

        let descriptions = errors.compactMap(\.errorDescription)
        #expect(descriptions.count == errors.count)
        #expect(Set(descriptions).count == errors.count)
    }

    @Test(
        "Export resolution maps to its pixel size",
        arguments: [
            (SaneExportSettings.ExportResolution.hd720, CGSize(width: 1280, height: 720)),
            (.hd1080, CGSize(width: 1920, height: 1080)),
            (.uhd4K, CGSize(width: 3840, height: 2160))
        ]
    )
    func resolutionSize(_ resolution: SaneExportSettings.ExportResolution, _ expected: CGSize) {
        #expect(resolution.size == expected)
    }
}
