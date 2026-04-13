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
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
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
      if contents.contains(".faceCaptureQuality") && !contents.contains("// Note:")
        && !contents.contains("legacy") {
        deprecatedUsages.append(
          "\(fileURL.lastPathComponent): Uses deprecated faceCaptureQuality without documentation")
      }
    }

    XCTAssertTrue(
      deprecatedUsages.isEmpty,
      "Found deprecated API usages:\n\(deprecatedUsages.joined(separator: "\n"))")
  }

  /// Ensures Translation framework uses modern TranslationSession API
  func testTranslationServiceUsesModernAPI() throws {
    let sourceDir = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
      .appendingPathComponent("SaneVideo/Services/AI")

    let translationServiceFile = sourceDir.appendingPathComponent("TranslationService.swift")
    guard let contents = try? String(contentsOf: translationServiceFile, encoding: .utf8) else {
      // File might not exist in test environment
      return
    }

    // Should use TranslationSession, not deprecated Translator
    XCTAssertTrue(
      contents.contains("TranslationSession"),
      "TranslationService should use TranslationSession API")
    XCTAssertFalse(
      contents.contains("Translator("),
      "TranslationService should not use deprecated Translator class")
    XCTAssertTrue(
      contents.contains("#if compiler(>=6.2)"),
      "TranslationService should guard direct TranslationSession initialization for older toolchains")
  }

  func testModernVideoCompositionAPIsAreCompilerGuarded() throws {
    let sourceRoot = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
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
        failureMessage)
    }
  }

  func testWhisperKitImportUsesPreconcurrencyShim() throws {
    let sourceRoot = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
      .appendingPathComponent("SaneVideo/Services/Captions/WhisperKitService.swift")

    guard let contents = try? String(contentsOf: sourceRoot, encoding: .utf8) else {
      XCTFail("Could not read WhisperKitService.swift")
      return
    }

    XCTAssertTrue(
      contents.contains("@preconcurrency import WhisperKit"),
      "WhisperKitService should import WhisperKit via @preconcurrency to keep strict-concurrency builds working on older toolchains")
  }

  /// Ensures CameraServiceProtocol uses async/await (modernized in macOS 26)
  func testCameraServiceUsesAsyncAPI() throws {
    let sourceDir = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
      .appendingPathComponent("SaneVideo/Core/Protocols")

    let protocolFile = sourceDir.appendingPathComponent("CameraServiceProtocol.swift")
    guard let contents = try? String(contentsOf: protocolFile, encoding: .utf8) else {
      return
    }

    // start() should be async throws, not use completion handlers
    XCTAssertTrue(
      contents.contains("func start() async throws"),
      "CameraServiceProtocol.start() should be async throws")
    XCTAssertFalse(
      contents.contains("start(completion:"),
      "CameraServiceProtocol should not have completion handler variant")
  }

  /// Ensures no usage of deprecated NSPersistentStore iCloud keys (removed in macOS 26)
  func testNoDeprecatedCoreDataiCloudKeys() throws {
    let sourceDir = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
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
      "Found removed Core Data iCloud keys:\n\(deprecatedUsages.joined(separator: "\n"))")
  }

  /// Ensures ExportEngine uses modern async export API (macOS 26)
  func testExportEngineUsesModernAsyncExport() throws {
    let sourceDir = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
      .appendingPathComponent("SaneVideo/Services/Export")

    let exportFile = sourceDir.appendingPathComponent("ExportEngine.swift")
    guard let contents = try? String(contentsOf: exportFile, encoding: .utf8) else { return }

    // Should have modern async export pattern
    XCTAssertTrue(
      contents.contains("export(to:") || contents.contains("async"),
      "ExportEngine should use modern async export API")
  }

  /// Regression: export sheet actions must resume UI work on the main actor.
  /// A background completion path caused a live crash in /Applications/SaneVideo.app
  /// on March 10, 2026 after Export File completed.
  func testExportViewActionsAreMainActorIsolated() throws {
    let sourceDir = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
      .appendingPathComponent("SaneVideo/Views/Export")

    let actionsFile = sourceDir.appendingPathComponent("ExportView+Actions.swift")
    guard let contents = try? String(contentsOf: actionsFile, encoding: .utf8) else { return }

    XCTAssertTrue(
      contents.contains("@MainActor\nextension ExportView"),
      "ExportView actions must be main-actor isolated before mutating SwiftUI state or dismissing sheets")
  }

  /// Regression: ExportEngine queue callbacks must not inherit main-actor isolation.
  /// The installed app crashed on March 10, 2026 when export completion resumed on
  /// the dedicated export queue while still carrying main-actor executor checks.
  func testExportEngineUsesNonisolatedQueueCallbacks() throws {
    let sourceDir = URL(fileURLWithPath: #file)
      .deletingLastPathComponent()  // Regression
      .deletingLastPathComponent()  // SaneVideoTests
      .deletingLastPathComponent()  // SaneVideo
      .appendingPathComponent("SaneVideo/Services/Export")

    let exportFile = sourceDir.appendingPathComponent("ExportEngine.swift")
    guard let contents = try? String(contentsOf: exportFile, encoding: .utf8) else { return }

    XCTAssertTrue(
      contents.contains("nonisolated(unsafe) let publishProgress"),
      "ExportEngine progress callbacks must be detached from the export queue's actor context")
    XCTAssertTrue(
      contents.contains("nonisolated(unsafe) let finalizeExport"),
      "ExportEngine completion callbacks must be detached from the export queue's actor context")
  }
}
