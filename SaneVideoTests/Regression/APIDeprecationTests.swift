//
//  APIDeprecationTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import XCTest

@testable import SaneVideo

final class APIDeprecationTests: XCTestCase {
    // MARK: - macOS 26 API Deprecation Guards

    /// Ensures no deprecated APIs are being used in the codebase
    /// These tests grep the source files to detect patterns that should be updated
    func testNoDeprecatedFaceCaptureQualityAPI() throws {
        // faceCaptureQuality was deprecated in macOS 26, should use captureQuality.score
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo")

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: nil)
        else {
            XCTFail("Could not enumerate source directory")
            return
        }

        var deprecatedUsages: [String] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            // Check for deprecated faceCaptureQuality (but allow documented legacy usage)
            if contents.contains(".faceCaptureQuality"), !contents.contains("// Note:"),
               !contents.contains("legacy") {
                deprecatedUsages.append(
                    "\(fileURL.lastPathComponent): Uses deprecated faceCaptureQuality without documentation")
            }
        }

        XCTAssertTrue(
            deprecatedUsages.isEmpty,
            "Found deprecated API usages:\n\(deprecatedUsages.joined(separator: "\n"))"
        )
    }

    /// Ensures Translation framework uses modern TranslationSession API
    func testTranslationServiceUsesModernAPI() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Services/AI")

        let translationServiceFile = sourceDir.appendingPathComponent("TranslationService.swift")
        guard let contents = try? String(contentsOf: translationServiceFile, encoding: .utf8) else {
            // File might not exist in test environment
            return
        }

        // Should use TranslationSession, not deprecated Translator
        XCTAssertTrue(
            contents.contains("TranslationSession"),
            "TranslationService should use TranslationSession API"
        )
        XCTAssertFalse(
            contents.contains("Translator("),
            "TranslationService should not use deprecated Translator class"
        )
        XCTAssertTrue(
            contents.contains("#if compiler(>=6.2)"),
            "TranslationService should guard direct TranslationSession initialization for older toolchains"
        )
    }

    func testModernVideoCompositionAPIsAreCompilerGuarded() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo")

        let guardedFiles = [
            "Services/Export/ExportCompositor.swift":
                "AVVideoComposition configuration APIs should be compiler-guarded in ExportCompositor",
            "Core/Engine/CompositionBuilder.swift":
                "AVVideoComposition configuration APIs should be compiler-guarded in CompositionBuilder",
            "Core/Engine/VideoTrackBuilder.swift":
                "AVVideoCompositionLayerInstruction configuration APIs should be compiler-guarded in VideoTrackBuilder"
        ]

        for (relativePath, failureMessage) in guardedFiles {
            let fileURL = sourceRoot.appendingPathComponent(relativePath)
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                XCTFail("Could not read \(relativePath)")
                continue
            }

            XCTAssertTrue(
                contents.contains("#if compiler(>=6.2)"),
                failureMessage
            )
        }
    }

    func testWhisperKitImportUsesPreconcurrencyShim() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Services/Captions/WhisperKitService.swift")

        guard let contents = try? String(contentsOf: sourceRoot, encoding: .utf8) else {
            XCTFail("Could not read WhisperKitService.swift")
            return
        }

        XCTAssertTrue(
            contents.contains("@preconcurrency import WhisperKit"),
            "WhisperKitService should import WhisperKit via @preconcurrency to keep strict-concurrency builds working on older toolchains"
        )
    }

    func testWhisperKitStaysOutOfDocumentsAndSkipsTestPreload() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Services/Captions/WhisperKitService.swift")

        let contents = try String(contentsOf: sourceRoot, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("TestEnvironment.isTesting"),
            "WhisperKit background preload should be suppressed in unit tests so it cannot hang the test host."
        )
        XCTAssertTrue(
            contents.contains(".applicationSupportDirectory"),
            "WhisperKit model downloads should live in Application Support, not the protected Documents folder."
        )
        XCTAssertTrue(
            contents.contains("config.downloadBase = try Self.modelDownloadBase()"),
            "WhisperKit should override the Hub default downloadBase; the upstream default is Documents/huggingface."
        )
        XCTAssertFalse(
            contents.contains(".documentDirectory"),
            "WhisperKitService must not request the user's Documents folder for model caches."
        )
    }

    /// Ensures CameraServiceProtocol uses async/await (modernized in macOS 26)
    func testCameraServiceUsesAsyncAPI() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Core/Protocols")

        let protocolFile = sourceDir.appendingPathComponent("CameraServiceProtocol.swift")
        guard let contents = try? String(contentsOf: protocolFile, encoding: .utf8) else {
            return
        }

        // start() should be async throws, not use completion handlers
        XCTAssertTrue(
            contents.contains("func start() async throws"),
            "CameraServiceProtocol.start() should be async throws"
        )
        XCTAssertFalse(
            contents.contains("start(completion:"),
            "CameraServiceProtocol should not have completion handler variant"
        )
    }

    /// Ensures no usage of deprecated NSPersistentStore iCloud keys (removed in macOS 26)
    func testNoDeprecatedCoreDataiCloudKeys() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo")

        let deprecatedKeys = [
            "NSPersistentStoreUbiquitousContentNameKey",
            "NSPersistentStoreUbiquitousContentURLKey",
            "NSPersistentStoreUbiquitousPeerTokenOption",
            "NSPersistentStoreRemoveUbiquitousMetadataOption",
            "NSPersistentStoreUbiquitousContainerIdentifierKey",
            "NSPersistentStoreRebuildFromUbiquitousContentOption"
        ]

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: sourceDir, includingPropertiesForKeys: nil)
        else { return }

        var deprecatedUsages: [String] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            for key in deprecatedKeys {
                if contents.contains(key) {
                    deprecatedUsages.append("\(fileURL.lastPathComponent): Uses removed \(key)")
                }
            }
        }

        XCTAssertTrue(
            deprecatedUsages.isEmpty,
            "Found removed Core Data iCloud keys:\n\(deprecatedUsages.joined(separator: "\n"))"
        )
    }

    /// Ensures ExportEngine uses modern async export API (macOS 26)
    func testExportEngineUsesModernAsyncExport() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Services/Export")

        let exportFile = sourceDir.appendingPathComponent("ExportEngine.swift")
        guard let contents = try? String(contentsOf: exportFile, encoding: .utf8) else { return }

        // Should have modern async export pattern
        XCTAssertTrue(
            contents.contains("export(to:") || contents.contains("async"),
            "ExportEngine should use modern async export API"
        )
    }

    /// Regression: export sheet actions must resume UI work on the main actor.
    /// A background completion path caused a live crash in /Applications/SaneVideo.app
    /// on March 10, 2026 after Export File completed.
    func testExportViewActionsAreMainActorIsolated() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Views/Export")

        let actionsFile = sourceDir.appendingPathComponent("ExportView+Actions.swift")
        guard let contents = try? String(contentsOf: actionsFile, encoding: .utf8) else { return }

        XCTAssertTrue(
            contents.contains("@MainActor\nextension ExportView"),
            "ExportView actions must be main-actor isolated before mutating SwiftUI state or dismissing sheets"
        )
    }

    /// Regression: export fallbacks must not silently write to Documents.
    /// macOS protected-folder prompts during export are customer-visible release blockers.
    func testExportViewActionsDoNotFallbackToDocuments() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Views/Export")

        let actionsFile = sourceDir.appendingPathComponent("ExportView+Actions.swift")
        guard let contents = try? String(contentsOf: actionsFile, encoding: .utf8) else { return }

        XCTAssertFalse(
            contents.contains("Exporting to Documents") || contents.contains(".documentDirectory"),
            "Export actions should use explicit user selection or app storage fallbacks, not Documents"
        )
    }

    /// Regression: camera startup must not trigger macOS Documents-folder prompts.
    /// iCloud sync services touch a Documents container, so they must stay lazy until
    /// the user opens/uses sync features.
    func testDocumentSyncServicesAreNotEagerAtLaunch() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let containerFile = sourceRoot
            .appendingPathComponent("SaneVideo/Core/DI/ServiceContainer.swift")
        let syncFile = sourceRoot
            .appendingPathComponent("SaneVideo/Services/Project/SyncManager.swift")
        let mediaAssetFile = sourceRoot
            .appendingPathComponent("SaneVideo/Services/Project/MediaAssetManager.swift")
        let iCloudSettingsFile = sourceRoot
            .appendingPathComponent("SaneVideo/Views/Settings/iCloudSyncSettingsView.swift")

        let container = try String(contentsOf: containerFile, encoding: .utf8)
        let sync = try String(contentsOf: syncFile, encoding: .utf8)
        let mediaAsset = try String(contentsOf: mediaAssetFile, encoding: .utf8)
        let iCloudSettings = try String(contentsOf: iCloudSettingsFile, encoding: .utf8)

        XCTAssertTrue(container.contains("lazy var syncManager"))
        XCTAssertTrue(container.contains("lazy var mediaAssetManager"))
        XCTAssertFalse(
            sync.contains("self.iCloudDocumentsURL = FileManager.default.url"),
            "SyncManager must not resolve iCloud Documents paths in init; that can trigger protected-folder prompts during unrelated startup flows."
        )
        XCTAssertFalse(
            mediaAsset.contains("self.iCloudMediaBase = FileManager.default.url"),
            "MediaAssetManager must not resolve iCloud Documents paths in init; unit tests and unrelated launch flows must not trigger protected-folder prompts."
        )
        XCTAssertTrue(
            sync.contains("SANEVIDEO_ENABLE_REAL_ICLOUD_TESTS"),
            "SyncManager should not query the real iCloud Documents container in normal unit tests."
        )
        XCTAssertTrue(
            mediaAsset.contains("SANEVIDEO_ENABLE_REAL_ICLOUD_TESTS"),
            "MediaAssetManager should not query the real iCloud Documents container in normal unit tests."
        )
        XCTAssertTrue(
            sync.contains("TestEnvironment.isTesting"),
            "SyncManager should use the shared test-environment detector before querying iCloud."
        )
        XCTAssertTrue(
            mediaAsset.contains("TestEnvironment.isTesting"),
            "MediaAssetManager should use the shared test-environment detector before querying iCloud."
        )
        XCTAssertFalse(
            iCloudSettings.contains("private let syncManager = SyncManager()"),
            "iCloud settings must not construct SyncManager before the user opens the iCloud tab."
        )
        XCTAssertTrue(
            iCloudSettings.contains("let isSelected: Bool"),
            "iCloud settings should know whether its tab is selected before starting sync checks."
        )
        XCTAssertTrue(
            iCloudSettings.contains(".task(id: isSelected)"),
            "iCloud settings should defer sync checks until the selected state changes."
        )
        XCTAssertTrue(
            iCloudSettings.contains("syncFeatureEnabledInThisBuild"),
            "iCloud settings should keep the v1 disabled-feature gate explicit."
        )
        XCTAssertFalse(
            iCloudSettings.contains("isCloudAvailable = await manager().isICloudAvailable"),
            "Opening iCloud settings must not probe the iCloud Documents container; that can trigger Documents-folder permission prompts."
        )
    }

    /// Regression: camera startup crashed on an EMEET SmartCam C960 4K after granting
    /// permission because the code constructed `CMTime(value: 1, timescale: fps)`,
    /// which did not exactly match the format's supported duration.
    func testCameraFrameRateUsesSupportedFormatDurations() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let cameraManagerFile = sourceRoot
            .appendingPathComponent("SaneVideo/Services/Camera/CameraManager.swift")
        let contents = try String(contentsOf: cameraManagerFile, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("supportedFrameDuration"),
            "CameraManager should select frame durations from AVCaptureDevice.Format supported ranges."
        )
        XCTAssertFalse(
            contents.contains("CMTime(value: 1, timescale: fpsInt)"),
            "CameraManager must not manually construct 1/fps durations; some cameras reject those exact CMTimes."
        )
    }

    /// Regression: camera startup timeout must not fire while macOS is still showing
    /// the first camera permission prompt.
    func testCameraStartTimeoutWaitsForAuthorizedPermissionState() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let cameraStateFile = sourceRoot
            .appendingPathComponent("SaneVideo/State/CameraState.swift")
        let contents = try String(contentsOf: cameraStateFile, encoding: .utf8)

        XCTAssertTrue(
            contents.contains("cameraAuthorizationStatus() == .authorized"),
            "CameraState should apply its hardware-start timeout only after camera permission is already authorized."
        )
        XCTAssertTrue(
            contents.contains("if shouldApplyStartTimeout"),
            "CameraState should not time out while the user is still answering the macOS camera prompt."
        )
    }

    /// Regression: mounting AVCaptureVideoPreviewLayer after startRunning caused
    /// AVFoundation to tear down and rebuild the capture graph, leaving a black
    /// preview after the user allowed camera access.
    func testCameraPublishesSessionBeforeStartingCaptureGraph() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let cameraManagerFile = sourceRoot
            .appendingPathComponent("SaneVideo/Services/Camera/CameraManager.swift")
        let contents = try String(contentsOf: cameraManagerFile, encoding: .utf8)

        guard let publishRange = contents.range(of: "self.session = session"),
              let startRange = contents.range(of: "session.startRunning()")
        else {
            XCTFail("CameraManager should publish the session and then start the capture graph.")
            return
        }

        XCTAssertLessThan(
            publishRange.lowerBound,
            startRange.lowerBound,
            "CameraManager should publish the session before startRunning so SwiftUI can mount the preview layer without forcing a post-start graph rebuild."
        )
        XCTAssertTrue(
            contents.contains("Task.sleep(nanoseconds: 100_000_000)"),
            "CameraManager should yield briefly so the preview layer can mount before the capture graph starts."
        )
    }

    /// Regression: the export sheet must fit normal laptop and desktop screens.
    /// A May 16, 2026 release check found the sheet running behind the Dock with
    /// hard-to-read dense helper copy.
    func testExportSheetIsBoundedAndReadable() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let exportView = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/ExportView.swift"),
            encoding: .utf8
        )
        let exportConfiguration = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Export/ExportConfigurationView.swift"),
            encoding: .utf8
        )
        let designSystem = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Core/DesignSystem.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            exportView.contains("ScrollView"),
            "ExportView needs a scrollable middle section so settings cannot run off-screen."
        )
        XCTAssertTrue(
            exportView.contains(".frame(maxHeight: 560)"),
            "ExportView should cap sheet content height for normal macOS screens."
        )
        XCTAssertTrue(
            exportConfiguration.contains("DisclosureGroup(isExpanded: $showAdvancedEffects)"),
            "Advanced AI export controls should be collapsed by default in the v1 export sheet."
        )
        XCTAssertFalse(
            exportView.contains("Export File is the quick path"),
            "ExportView should not add dense explanatory paragraphs above the export controls."
        )
        XCTAssertTrue(
            designSystem.contains("textSecondary = Color.white.opacity(0.92)"),
            "SaneVideo support text should stay bright enough on dark materials."
        )
    }

    /// Regression: the post-recording Share action used to open ExportView without
    /// adding the just-recorded file to the project, leaving export stuck at 0 MB.
    func testQuickAccessShareImportsRecordingBeforeExport() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let actions = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/State/AppState+Actions.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            actions.contains("prepareQuickAccessRecordingForTimeline(url: url)"),
            "Quick-access Share must prepare a project timeline before opening export."
        )
        XCTAssertTrue(
            actions.contains("await projectState.addVideoToTimeline(url: url)"),
            "Quick-access recordings must be added to the timeline before export can estimate or render them."
        )
        XCTAssertTrue(
            actions.contains("self.showExportSheet = true"),
            "Export sheet should open only after the recording has been prepared for the timeline."
        )
    }

    /// Regression: public testing pricing must stay aligned with the website and direct checkout.
    func testPublicTestingPricingCopyMatchesReleaseOffer() throws {
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo

        let pricing = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Core/Configuration/PricingConfiguration.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(pricing.contains("case .launch: return \"Free\""))
        XCTAssertTrue(pricing.contains("case .regular: return \"Free\""))
        XCTAssertTrue(pricing.contains("Launch-period discount path is retired. SaneVideo is free."))
        XCTAssertTrue(pricing.contains("Free and open source. Donate only if you want to support it."))
        XCTAssertTrue(pricing.contains("Every recording and edit tool stays unlocked."))
        XCTAssertFalse(pricing.contains("Enjoy 14 days of Pro"))
        XCTAssertFalse(pricing.contains("Try Pro free for 14 days"))
        XCTAssertFalse(pricing.contains("Launch Special: $29"))
        XCTAssertFalse(pricing.contains("case .regular: return \"$49\""))
        XCTAssertFalse(pricing.contains("Everything included. One price. Forever."))
    }

    /// Regression: ExportEngine queue callbacks must not inherit main-actor isolation.
    /// The installed app crashed on March 10, 2026 when export completion resumed on
    /// the dedicated export queue while still carrying main-actor executor checks.
    func testExportEngineUsesNonisolatedQueueCallbacks() throws {
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // Regression
            .deletingLastPathComponent() // SaneVideoTests
            .deletingLastPathComponent() // SaneVideo
            .appendingPathComponent("SaneVideo/Services/Export")

        let exportFile = sourceDir.appendingPathComponent("ExportEngine.swift")
        guard let contents = try? String(contentsOf: exportFile, encoding: .utf8) else { return }

        XCTAssertTrue(
            contents.contains("nonisolated(unsafe) let publishProgress"),
            "ExportEngine progress callbacks must be detached from the export queue's actor context"
        )
        XCTAssertTrue(
            contents.contains("nonisolated(unsafe) let finalizeExport"),
            "ExportEngine completion callbacks must be detached from the export queue's actor context"
        )
    }
}
