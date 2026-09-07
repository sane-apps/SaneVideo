//
//  UserPreferences.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import Combine
import SwiftUI

/// Manages persistent user preferences using UserDefaults
/// SWIFT 6 FIX: @MainActor required for UI-driving state (SwiftUI views read preferences)
@MainActor
@Observable
class UserPreferences {

  // MARK: - Properties with Manual Observation

  var appTheme: AppTheme {
    get {
      access(keyPath: \.appTheme)
      return _appTheme
    }
    set {
      withMutation(keyPath: \.appTheme) {
        _appTheme = newValue
      }
    }
  }

  var defaultResolution: SaneExportSettings.ExportResolution {
    get {
      access(keyPath: \.defaultResolution)
      return _defaultResolution
    }
    set {
      withMutation(keyPath: \.defaultResolution) {
        _defaultResolution = newValue
      }
    }
  }

  var defaultCodec: String {
    get {
      access(keyPath: \.defaultCodec)
      return _defaultCodec
    }
    set {
      withMutation(keyPath: \.defaultCodec) {
        _defaultCodec = newValue
      }
    }
  }

  // MARK: - Underlying Storage

  @ObservationIgnored @AppStorage("AppTheme") private var _appTheme: AppTheme = .system
  @ObservationIgnored @AppStorage("DefaultExportResolution") private var _defaultResolution:
    SaneExportSettings.ExportResolution = .uhd4K
  @ObservationIgnored @AppStorage("DefaultExportCodec") private var _defaultCodec: String = "hvc1"
  @ObservationIgnored @AppStorage("TranscriptionEngine") private var _transcriptionEngine: String =
    TranscriptionEngine.default.rawValue
  @ObservationIgnored @AppStorage("RecordingResolution") private var _recordingResolution: String =
    SaneExportSettings.ExportResolution.hd1080.rawValue
  @ObservationIgnored @AppStorage("RecordingFPS") private var _recordingFPS: Double = 60.0
  @ObservationIgnored @AppStorage("ExcludeAppFromRecording") private var _excludeAppFromRecording:
    Bool = true
  @ObservationIgnored @AppStorage(CameraPreviewMirroring.appStorageKey) private var _mirrorCameraPreview:
    Bool = CameraPreviewMirroring.defaultIsMirrored

  // Helper to get typed AVVideoCodecType (since AppStorage doesn't support it directly)
  var defaultAVCodec: AVVideoCodecType {
    get { AVVideoCodecType(rawValue: defaultCodec) }
    set { defaultCodec = newValue.rawValue }
  }

  var recordingResolution: SaneExportSettings.ExportResolution {
    get {
      access(keyPath: \.recordingResolution)
      return SaneExportSettings.ExportResolution(rawValue: _recordingResolution) ?? .hd1080
    }
    set {
      withMutation(keyPath: \.recordingResolution) {
        _recordingResolution = newValue.rawValue
      }
    }
  }

  var recordingFPS: Double {
    get {
      access(keyPath: \.recordingFPS)
      return _recordingFPS
    }
    set {
      withMutation(keyPath: \.recordingFPS) {
        _recordingFPS = newValue
      }
    }
  }

  var excludeAppFromRecording: Bool {
    get {
      access(keyPath: \.excludeAppFromRecording)
      return _excludeAppFromRecording
    }
    set {
      withMutation(keyPath: \.excludeAppFromRecording) {
        _excludeAppFromRecording = newValue
      }
    }
  }

  var mirrorCameraPreview: Bool {
    get {
      access(keyPath: \.mirrorCameraPreview)
      return _mirrorCameraPreview
    }
    set {
      withMutation(keyPath: \.mirrorCameraPreview) {
        _mirrorCameraPreview = newValue
      }
    }
  }

  var transcriptionEngine: TranscriptionEngine {
    get {
      access(keyPath: \.transcriptionEngine)
      return TranscriptionEngine(rawValue: _transcriptionEngine) ?? .default
    }
    set {
      withMutation(keyPath: \.transcriptionEngine) {
        _transcriptionEngine = newValue.rawValue
      }
    }
  }

  init() {}

  // MARK: - Cache Management

  func clearCache(
    thumbnailService: any ThumbnailServiceProtocol,
    waveformService: any WaveformServiceProtocol
  ) async {
    // Preview caches are disposable; recordings and project assets are not.
    await thumbnailService.clearCache()
    await waveformService.clearCache()
    AppLogger.uiLog.info("Preview caches cleared successfully")
  }

}

enum AppTheme: String, CaseIterable, Identifiable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String { rawValue }
}
