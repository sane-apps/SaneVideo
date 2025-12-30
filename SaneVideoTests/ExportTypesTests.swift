//
//  ExportTypesTests.swift
//  SaneVideoTests
//
//  Tests for ExportTypes - error handling, export settings, resolution mappings
//

import Testing
import AVFoundation
@testable import SaneVideo

@Suite("Export Types Tests")
struct ExportTypesTests {

    // MARK: - ExportError Tests

    @Suite("ExportError")
    struct ExportErrorTests {

        @Test("alreadyExporting has clear error description")
        func alreadyExportingDescription() {
            // Arrange
            let error = ExportError.alreadyExporting

            // Assert
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.contains("already") == true)
        }

        @Test("failedToCreateSession has clear error description")
        func failedToCreateSessionDescription() {
            // Arrange
            let error = ExportError.failedToCreateSession

            // Assert
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.lowercased().contains("session") == true)
        }

        @Test("cancelled has clear error description")
        func cancelledDescription() {
            // Arrange
            let error = ExportError.cancelled

            // Assert
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.lowercased().contains("cancel") == true)
        }

        @Test("invalidProject includes custom message")
        func invalidProjectDescription() {
            // Arrange
            let customMessage = "Project has no video clips"
            let error = ExportError.invalidProject(customMessage)

            // Assert
            #expect(error.errorDescription == customMessage)
        }

        @Test("timeout has clear error description")
        func timeoutDescription() {
            // Arrange
            let error = ExportError.timeout

            // Assert
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.lowercased().contains("timeout") == true || error.errorDescription?.lowercased().contains("timed out") == true)
        }

        @Test("insufficientDiskSpace formats bytes correctly")
        func insufficientDiskSpaceDescription() {
            // Arrange
            let required: Int64 = 1_000_000_000 // 1 GB
            let available: Int64 = 500_000_000 // 500 MB
            let error = ExportError.insufficientDiskSpace(required: required, available: available)

            // Assert
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.contains("disk space") == true || error.errorDescription?.contains("Disk") == true)
            #expect(error.errorDescription?.contains("GB") == true || error.errorDescription?.contains("MB") == true)
        }

        @Test("unknown has fallback error description")
        func unknownDescription() {
            // Arrange
            let error = ExportError.unknown

            // Assert
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }

        @Test("All errors have unique descriptions")
        func allErrorsHaveUniqueDescriptions() {
            // Arrange
            let errors: [ExportError] = [
                .alreadyExporting,
                .failedToCreateSession,
                .cancelled,
                .invalidProject("test"),
                .timeout,
                .insufficientDiskSpace(required: 1000, available: 500),
                .unknown
            ]

            // Act
            let descriptions = errors.compactMap { $0.errorDescription }

            // Assert
            #expect(descriptions.count == 7)
            let uniqueDescriptions = Set(descriptions)
            #expect(uniqueDescriptions.count == 7)
        }
    }

    // MARK: - SaneExportSettings Tests

    @Suite("SaneExportSettings")
    struct SaneExportSettingsTests {

        @Test("Default settings have correct values")
        func defaultSettings() {
            // Arrange & Act
            let settings = SaneExportSettings()

            // Assert
            #expect(settings.codec == .hevc)
            #expect(settings.resolution == .uhd4K)
            #expect(settings.bitrate == 20_000_000)
            #expect(settings.frameRate == 60.0)
        }

        @Test("Custom settings preserve values")
        func customSettings() {
            // Arrange & Act
            let settings = SaneExportSettings(
                codec: .h264,
                resolution: .hd1080,
                bitrate: 10_000_000,
                frameRate: 30.0
            )

            // Assert
            #expect(settings.codec == .h264)
            #expect(settings.resolution == .hd1080)
            #expect(settings.bitrate == 10_000_000)
            #expect(settings.frameRate == 30.0)
        }

        @Test("Settings are Codable - encode and decode")
        func settingsCodable() throws {
            // Arrange
            let original = SaneExportSettings(
                codec: .proRes422,
                resolution: .hd720,
                bitrate: 5_000_000,
                frameRate: 24.0
            )

            // Act
            let encoder = JSONEncoder()
            let data = try encoder.encode(original)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(SaneExportSettings.self, from: data)

            // Assert
            #expect(decoded.codec == original.codec)
            #expect(decoded.resolution == original.resolution)
            #expect(decoded.bitrate == original.bitrate)
            #expect(decoded.frameRate == original.frameRate)
        }

        @Test("Settings preserve HEVC codec through encoding")
        func hevcCodecCodable() throws {
            // Arrange
            let original = SaneExportSettings(codec: .hevc)

            // Act
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(SaneExportSettings.self, from: data)

            // Assert
            #expect(decoded.codec == .hevc)
        }

        @Test("Settings preserve H264 codec through encoding")
        func h264CodecCodable() throws {
            // Arrange
            let original = SaneExportSettings(codec: .h264)

            // Act
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(SaneExportSettings.self, from: data)

            // Assert
            #expect(decoded.codec == .h264)
        }
    }

    // MARK: - ExportResolution Tests

    @Suite("ExportResolution")
    struct ExportResolutionTests {

        @Test("720p has correct size")
        func hd720Size() {
            // Arrange & Act
            let resolution = SaneExportSettings.ExportResolution.hd720

            // Assert
            #expect(resolution.size.width == 1280)
            #expect(resolution.size.height == 720)
        }

        @Test("1080p has correct size")
        func hd1080Size() {
            // Arrange & Act
            let resolution = SaneExportSettings.ExportResolution.hd1080

            // Assert
            #expect(resolution.size.width == 1920)
            #expect(resolution.size.height == 1080)
        }

        @Test("4K has correct size")
        func uhd4KSize() {
            // Arrange & Act
            let resolution = SaneExportSettings.ExportResolution.uhd4K

            // Assert
            #expect(resolution.size.width == 3840)
            #expect(resolution.size.height == 2160)
        }

        @Test("All resolutions have display names")
        func displayNames() {
            // Arrange
            let resolutions: [SaneExportSettings.ExportResolution] = [.hd720, .hd1080, .uhd4K]

            // Act & Assert
            for resolution in resolutions {
                #expect(resolution.displayName.isEmpty == false)
            }
        }

        @Test("Resolution raw values are correct")
        func rawValues() {
            // Assert
            #expect(SaneExportSettings.ExportResolution.hd720.rawValue == "720p")
            #expect(SaneExportSettings.ExportResolution.hd1080.rawValue == "1080p")
            #expect(SaneExportSettings.ExportResolution.uhd4K.rawValue == "4K")
        }

        @Test("Resolution is Codable")
        func resolutionCodable() throws {
            // Arrange
            let original = SaneExportSettings.ExportResolution.hd1080

            // Act
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(SaneExportSettings.ExportResolution.self, from: data)

            // Assert
            #expect(decoded == original)
        }

        @Test("All resolutions can be initialized from raw value")
        func initFromRawValue() {
            // Assert
            #expect(SaneExportSettings.ExportResolution(rawValue: "720p") == .hd720)
            #expect(SaneExportSettings.ExportResolution(rawValue: "1080p") == .hd1080)
            #expect(SaneExportSettings.ExportResolution(rawValue: "4K") == .uhd4K)
            #expect(SaneExportSettings.ExportResolution(rawValue: "invalid") == nil)
        }
    }
}
