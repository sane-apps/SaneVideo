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
    @ObservationIgnored @AppStorage("DefaultExportResolution") private var _defaultResolution: SaneExportSettings.ExportResolution = .uhd4K
    @ObservationIgnored @AppStorage("DefaultExportCodec") private var _defaultCodec: String = "hvc1"

    // Helper to get typed AVVideoCodecType (since AppStorage doesn't support it directly)
    var defaultAVCodec: AVVideoCodecType {
        get { AVVideoCodecType(rawValue: defaultCodec) }
        set { defaultCodec = newValue.rawValue }
    }

    init() {}

    // MARK: - Cache Management

    func clearCache() {
        // Clear temp directory
        let tempDir = FileManager.default.temporaryDirectory
        Task.detached(priority: .utility) {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    try FileManager.default.removeItem(at: fileURL)
                }
                await MainActor.run {
                    AppLogger.uiLog.info("Cache cleared successfully")
                }
            } catch {
                await MainActor.run {
                    AppLogger.uiLog.error("Failed to clear cache: \(error)")
                }
            }
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}
