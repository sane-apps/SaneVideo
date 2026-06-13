//
//  AutomationRailStateTests.swift
//  SaneVideoTests
//
//  Proves the four left-rail editor states (Transcript, Thumbnail, Voiceover, Shorts)
//  can be activated programmatically by automation runs.
//

import Foundation
@testable import SaneVideo
import Testing

/// Thread-safe notification probe (NotificationCenter observer blocks are @Sendable).
private final class NotificationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedNames: [Notification.Name] = []

    var received: [Notification.Name] {
        lock.lock()
        defer { lock.unlock() }
        return receivedNames
    }

    func record(_ name: Notification.Name) {
        lock.lock()
        defer { lock.unlock() }
        receivedNames.append(name)
    }
}

@Suite("Automation Rail State")
struct AutomationRailStateTests {
    @Test(
        "Parses each rail state from AUTOMATION_RAIL_STATE",
        arguments: AutomationRailState.allCases
    )
    func parsesEachRailStateFromEnvironment(_ state: AutomationRailState) {
        #expect(
            TestEnvironment.automationRailState(
                in: ["AUTOMATION_RAIL_STATE": state.rawValue]
            ) == state
        )
    }

    @Test("Parses rail state from launch arguments in both supported spellings")
    func parsesRailStateFromLaunchArguments() {
        #expect(
            TestEnvironment.automationRailState(
                arguments: ["-automation_rail_state", "thumbnail"],
                environment: [:]
            ) == .thumbnail
        )
        #expect(
            TestEnvironment.automationRailState(
                arguments: ["--automation-rail-state=shorts"],
                environment: [:]
            ) == .shorts
        )
    }

    @Test("Accepts the SANEVIDEO_-prefixed variant forwarded by shared launch tooling")
    func acceptsPrefixedEnvironmentVariant() {
        #expect(
            TestEnvironment.automationRailState(
                in: ["SANEVIDEO_AUTOMATION_RAIL_STATE": "voiceover"]
            ) == .voiceover
        )
    }

    @Test("Normalizes case and surrounding whitespace")
    func normalizesCaseAndWhitespace() {
        #expect(
            TestEnvironment.automationRailState(
                in: ["AUTOMATION_RAIL_STATE": " Voiceover \n"]
            ) == .voiceover
        )
    }

    @Test("Rejects unknown, empty, and missing values")
    func rejectsUnknownValues() {
        #expect(TestEnvironment.automationRailState(in: ["AUTOMATION_RAIL_STATE": "exports"]) == nil)
        #expect(TestEnvironment.automationRailState(in: ["AUTOMATION_RAIL_STATE": ""]) == nil)
        #expect(TestEnvironment.automationRailState(in: [:]) == nil)
    }

    @Test("Requesting a rail state launches straight into the editor")
    func railStateRequestsEditorBootstrap() throws {
        let suiteName = "AutomationRailStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            TestEnvironment.shouldOpenEditor(
                arguments: [],
                userDefaults: defaults,
                environment: ["AUTOMATION_RAIL_STATE": "transcript"]
            )
        )
        #expect(
            !TestEnvironment.shouldOpenEditor(
                arguments: [],
                userDefaults: defaults,
                environment: ["AUTOMATION_RAIL_STATE": "not-a-rail-state"]
            )
        )
    }

    @Test("Each rail state maps to the notification its left-rail control posts")
    func mapsToRailControlNotifications() {
        #expect(AutomationRailState.transcript.notificationName.rawValue == "ShowSidebarTranscript")
        #expect(AutomationRailState.thumbnail.notificationName.rawValue == "GenerateThumbnail")
        #expect(AutomationRailState.voiceover.notificationName.rawValue == "GenerateVoiceover")
        #expect(AutomationRailState.shorts.notificationName.rawValue == "ShowRepurposingSheet")
    }

    @Test(
        "Activating each rail state posts exactly its rail control notification",
        arguments: AutomationRailState.allCases
    )
    @MainActor
    func activationPostsRailNotification(_ state: AutomationRailState) {
        let appState = AppState()
        let probe = NotificationProbe()

        let observers = AutomationRailState.allCases.map { candidate in
            NotificationCenter.default.addObserver(
                forName: candidate.notificationName,
                object: nil,
                queue: nil
            ) { notification in
                probe.record(notification.name)
            }
        }
        defer {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        appState.activateAutomationRailState(state)

        #expect(probe.received == [state.notificationName])
    }
}
