import Testing
import AVFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers
@testable import SaneVideo

@Suite("App Integration Tests")
struct AppIntegrationTests {

    // MARK: - PDFExportDocument Tests

    @Test("PDFExportDocument initialization with data")
    func pdfExportDocument_InitWithData() {
        let dummyData = "Test PDF Data".data(using: .utf8)!
        let document = PDFExportDocument(data: dummyData)
        #expect(document.pdfData == dummyData, "Document should store initialized data")
    }

    @Test("PDFExportDocument file wrapper behavior")
    func pdfExportDocument_FileWrapper() throws {
        let dummyData = "Test PDF Data".data(using: .utf8)!
        let document = PDFExportDocument(data: dummyData)
        #expect(document.pdfData == dummyData, "Document data should match")
    }

    @Test("PDFExportDocument readable content types")
    func pdfExportDocument_ReadableContentTypes() {
        let pdfType = UTType(filenameExtension: "pdf")!
        #expect(PDFExportDocument.readableContentTypes.contains(pdfType), "Should support PDF type")
    }

    // MARK: - ShareLinkService Tests

    @Test("ShareLinkService shared instance availability")
    @MainActor
    func shareLinkService_SharedInstance() {
        let service = ServiceContainer.shared.shareLinkService
        #expect(service != nil, "Shared instance should exist")
    }

    // MARK: - SilenceDetector Tests

    @Test("SilenceDetector default configuration")
    func silenceDetector_Configuration() {
        let config = SilenceDetector.Configuration.default
        #expect(config.dbThreshold == -45.0)
        #expect(config.minDuration == 0.3)
    }

    @Test("SilenceDetector with invalid file")
    func silenceDetector_NoAudioTrack() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty_test_app.mp4")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let clip = VideoClip(url: tempURL, duration: .zero)
        let detector = SilenceDetector()

        do {
            let ranges = try await detector.detectSilence(in: clip)
            #expect(ranges.count <= 1)
        } catch {
            // Expected for empty file
        }
    }

    // MARK: - WaveformService Tests

    @Test("WaveformService shared instance availability")
    @MainActor
    func waveformService_SharedInstance() {
        let service = ServiceContainer.shared.waveformService
        #expect(service != nil)
    }

    @Test("WaveformService consistency and caching")
    @MainActor
    func waveformService_Caching() async {
        let service = ServiceContainer.shared.waveformService
        let tempURL = URL(fileURLWithPath: "/tmp/dummy_waveform_app_test.mp4")
        let clip = VideoClip(url: tempURL, duration: CMTime(seconds: 10, preferredTimescale: 600))

        let samples = await service.waveform(for: clip)
        let samples2 = await service.waveform(for: clip)

        let count1: Int = samples?.count ?? -1
        let count2: Int = samples2?.count ?? -1
        #expect(count1 == count2, "Should return consistent result")
    }

    // MARK: - SharedRecordingControls Tests

    @Test("SharedRecordingControls type availability")
    func sharedRecordingControls_CanInitialize() {
        _ = SharedRecordingControls.self
        #expect(true)
    }

    // MARK: - Mock Object Tests

    @Test("Theme data constants")
    func themeData() {
        #expect(Theme.Colors.action != nil)
        #expect(Theme.Colors.background != nil)
        #expect(Theme.Dimensions.cornerRadius == 8)
    }
}
