//
//  UpdaterServiceTests.swift
//  SaneVideoTests
//
//  Tests for UpdaterService - Sparkle auto-update integration
//

import Testing
import Foundation
@testable import SaneVideo

@Suite("UpdaterService Tests")
struct UpdaterServiceTests {

    // MARK: - Initialization Tests

    @MainActor
    @Test("UpdaterService initializes with canCheckForUpdates ready")
    func updaterServiceInitializes() {
        // Arrange & Act
        let service = UpdaterService()

        // Assert - startingUpdater:true should make Sparkle ready immediately in direct builds
        #expect(service.canCheckForUpdates == true, "canCheckForUpdates should be true once Sparkle starts immediately")
    }

    @MainActor
    @Test("UpdaterService accepts valid appcast feeds")
    func appcastValidationAcceptsRSS() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
          <channel>
            <title>SaneVideo Updates</title>
            <item>
              <title>Version 1.0</title>
            </item>
          </channel>
        </rss>
        """

        #expect(UpdaterService.looksLikeAppcastFeed(Data(xml.utf8)))
    }

    @Test("UpdaterService rejects non-appcast responses")
    func appcastValidationRejectsHTML() {
        let html = """
        <html>
          <head><title>Coming Soon</title></head>
          <body>Parking page</body>
        </html>
        """

        #expect(!UpdaterService.looksLikeAppcastFeed(Data(html.utf8)))
    }
}
