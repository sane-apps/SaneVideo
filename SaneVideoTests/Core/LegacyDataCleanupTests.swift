//
//  LegacyDataCleanupTests.swift
//  SaneVideoTests
//
//  One-time removal of data from removed features, against a temp Application Support folder and a
//  throwaway UserDefaults suite. (It also deletes the app's old API-key keychain item, as the app does.)
//

import Foundation
@testable import SaneVideo
import Testing

@Suite("Legacy Data Cleanup")
struct LegacyDataCleanupTests {
    /// Points Application Support at a temp folder; everything else is the real FileManager.
    private final class SandboxFileManager: FileManager, @unchecked Sendable {
        let support: URL

        init(support: URL) {
            self.support = support
            super.init()
        }

        override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
            directory == .applicationSupportDirectory ? [support] : super.urls(for: directory, in: domainMask)
        }
    }

    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suiteName: String
        let fileManager: SandboxFileManager

        var whisperModels: URL {
            root.appendingPathComponent("SaneVideo/WhisperKitModels", isDirectory: true)
        }

        var keptFile: URL {
            root.appendingPathComponent("SaneVideo/Projects/keep.txt")
        }

        func seedLegacyData() throws {
            try FileManager.default.createDirectory(at: whisperModels, withIntermediateDirectories: true)
            try Data("model".utf8).write(to: whisperModels.appendingPathComponent("weights.bin"))
            defaults.set(true, forKey: "iCloudSyncEnabled")
            defaults.set("whisperKit", forKey: "TranscriptionEngine")
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = try TestMedia.makeTempDirectory("LegacyCleanup")
        let suiteName = "LegacyDataCleanupTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let sandbox = Sandbox(root: root, defaults: defaults, suiteName: suiteName, fileManager: SandboxFileManager(support: root))
        try FileManager.default.createDirectory(at: sandbox.keptFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("project".utf8).write(to: sandbox.keptFile)
        defaults.set("keep", forKey: "unrelated")
        return sandbox
    }

    @Test("Removes the WhisperKit model folder and the removed-feature settings, keeping everything else")
    func removesLegacyData() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.tearDown() }
        try sandbox.seedLegacyData()

        LegacyDataCleanup.runOnce(defaults: sandbox.defaults, fileManager: sandbox.fileManager)

        #expect(!FileManager.default.fileExists(atPath: sandbox.whisperModels.path))
        #expect(FileManager.default.fileExists(atPath: sandbox.keptFile.path))
        #expect(sandbox.defaults.object(forKey: "iCloudSyncEnabled") == nil)
        #expect(sandbox.defaults.object(forKey: "TranscriptionEngine") == nil)
        #expect(sandbox.defaults.string(forKey: "unrelated") == "keep")
    }

    @Test("Runs only once: later launches leave new data alone")
    func runsOnlyOnce() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.tearDown() }
        LegacyDataCleanup.runOnce(defaults: sandbox.defaults, fileManager: sandbox.fileManager)

        try sandbox.seedLegacyData()
        LegacyDataCleanup.runOnce(defaults: sandbox.defaults, fileManager: sandbox.fileManager)

        #expect(FileManager.default.fileExists(atPath: sandbox.whisperModels.path))
        #expect(sandbox.defaults.string(forKey: "TranscriptionEngine") == "whisperKit")
    }
}
