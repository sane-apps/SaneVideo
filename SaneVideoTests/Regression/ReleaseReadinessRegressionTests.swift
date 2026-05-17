import XCTest

final class ReleaseReadinessRegressionTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testLibraryDeleteFromDiskHasReachableConfirmation() throws {
        let libraryView = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Components/LibraryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(libraryView.contains("LibraryClipContextMenu(clip: clip)"))
        XCTAssertTrue(libraryView.contains("onRequestDeleteFile()"))
        XCTAssertTrue(libraryView.contains("sidebar.delete_disk_confirm"))
    }

    func testExportShareIsDisabledForEmptyTimeline() throws {
        let exportView = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/ExportView.swift"),
            encoding: .utf8
        )
        let exportActions = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Export/ExportView+Actions.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(exportView.contains(".disabled(isExporting || youtubeService.isUploading || isTimelineEmpty)"))
        XCTAssertTrue(exportActions.contains("Add at least one clip before sharing an exported file."))
    }

    func testCustomerSettingsAndTextContrastAreReleaseTight() throws {
        let mainContent = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/MainContentView.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let privacySettings = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Settings/PrivacySettingsView.swift"),
            encoding: .utf8
        )
        let designSystem = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Core/DesignSystem.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settings.contains("#if DEBUG"))
        XCTAssertTrue(mainContent.contains("#if DEBUG"))
        XCTAssertTrue(mainContent.contains("BuildTimestampView()"))
        XCTAssertTrue(settings.contains("PrivacySettingsView(selectedTab: $selectedTab)"))
        XCTAssertTrue(privacySettings.contains("selectedTab = \"apikeys\""))
        XCTAssertFalse(privacySettings.contains("NavigationLink"))
        XCTAssertTrue(designSystem.contains("static let stone = Color.white.opacity(0.9)"))
    }

    func testPurchaseAndPermissionCopyAvoidsV1PromiseDrift() throws {
        let appSource = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/SaneVideoApp.swift"), encoding: .utf8)
        let appError = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Core/AppError.swift"), encoding: .utf8)
        let exportConfiguration = try String(
            contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Views/Export/ExportConfigurationView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(appSource.contains("Cloud sync for project assets"))
        XCTAssertTrue(appSource.contains("Pro export presets and creator workflow tools"))
        XCTAssertTrue(appError.contains("Screen Recording Permission Required"))
        XCTAssertTrue(appError.contains("Screen & System Audio Recording access"))
        XCTAssertTrue(exportConfiguration.contains(".frame(minWidth: 220, maxWidth: 260"))
    }

    func testAppStoreLaneIsSeparateFromDirectSparkleLane() throws {
        let project = try String(contentsOf: sourceRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let appSource = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/SaneVideoApp.swift"), encoding: .utf8)
        let appStorePlist = try String(contentsOf: sourceRoot.appendingPathComponent("SaneVideo/Info-AppStore.plist"), encoding: .utf8)

        XCTAssertTrue(project.contains("SaneVideoAppStore:"))
        XCTAssertTrue(project.contains("INFOPLIST_FILE: SaneVideo/Info-AppStore.plist"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_AppStoreProductID: com.sanevideo.app.pro.unlock"))
        XCTAssertTrue(project.contains("CODE_SIGN_IDENTITY: \"Apple Distribution\""))
        XCTAssertFalse(appSource.contains("https://go.saneapps.com/buy/sanevideo"))
        XCTAssertTrue(appSource.contains("LicenseService.directCheckoutURL(appSlug: \"sanevideo\")"))
        XCTAssertTrue(appStorePlist.contains("<key>AppStoreProductID</key>"))
        XCTAssertFalse(appStorePlist.contains("SUFeedURL"))
        XCTAssertFalse(appStorePlist.contains("SUPublicEDKey"))
    }

    func testAppStoreScreenshotStoryboardAndGeneratorCoverLaunchSellingPoints() throws {
        let storyboardURL = sourceRoot.appendingPathComponent("docs/appstore_screenshot_storyboard.yml")
        let generatorURL = sourceRoot.appendingPathComponent("scripts/generate_appstore_screenshots.swift")
        let storyboard = try String(contentsOf: storyboardURL, encoding: .utf8)
        let generator = try String(contentsOf: generatorURL, encoding: .utf8)

        XCTAssertTrue(storyboard.contains("Record screen, camera, and mic"))
        XCTAssertTrue(storyboard.contains("Edit locally on a timeline"))
        XCTAssertTrue(storyboard.contains("Export local files with presets"))
        XCTAssertTrue(storyboard.contains("Captions and demo packs"))
        XCTAssertTrue(storyboard.contains("must_not_show:"))
        XCTAssertTrue(storyboard.contains("build timestamp"))

        XCTAssertTrue(generator.contains("appstore-01-recording-dark-mac.png"))
        XCTAssertTrue(generator.contains("appstore-02-editing-dark-mac.png"))
        XCTAssertTrue(generator.contains("appstore-03-export-dark-mac.png"))
        XCTAssertTrue(generator.contains("appstore-04-captions-demo-pack-dark-mac.png"))
        XCTAssertFalse(generator.contains("YouTube upload unavailable"))
        XCTAssertFalse(generator.contains("Disabled in v1"))
    }
}
