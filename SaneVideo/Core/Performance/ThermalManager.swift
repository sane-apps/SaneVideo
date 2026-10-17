import Foundation
import SwiftUI
import Observation

enum PerformanceLevel: String, CaseIterable, Sendable {
    case high        // Thermal state: nominal
    case balanced    // Thermal state: fair
    case throttled   // Thermal state: serious
    case emergency   // Thermal state: critical
}

@MainActor
@Observable
final class ThermalManager {
    static let shared = ThermalManager()
    
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    
    var performanceLevel: PerformanceLevel {
        Self.performanceLevel(for: thermalState)
    }
    
    var isThermalPressureHigh: Bool {
        Self.isThermalPressureHigh(for: thermalState)
    }
    
    // MARK: - Non-isolated static accessors for background threads
    
    /// Synchronously checks if thermal pressure is high without actor isolation.
    nonisolated static var isThrottled: Bool {
        isThermalPressureHigh(for: ProcessInfo.processInfo.thermalState)
    }
    
    /// Synchronously checks if system is in emergency state without actor isolation.
    nonisolated static var isEmergency: Bool {
        ProcessInfo.processInfo.thermalState == .critical
    }
    
    // MARK: - Internal Logic
    
    nonisolated static func performanceLevel(for state: ProcessInfo.ThermalState) -> PerformanceLevel {
        switch state {
        case .nominal: return .high
        case .fair:    return .balanced
        case .serious: return .throttled
        case .critical: return .emergency
        @unknown default: return .high
        }
    }
    
    nonisolated static func isThermalPressureHigh(for state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }
    
    private init() {
        self.thermalState = ProcessInfo.processInfo.thermalState
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateThermalState()
            }
        }
    }
    
    private func updateThermalState() {
        let newState = ProcessInfo.processInfo.thermalState
        if newState != thermalState {
            thermalState = newState
            AppLogger.general.info("🔥 Thermal State Changed: \(String(describing: newState)) -> Recommended Level: \(self.performanceLevel.rawValue)")
        }
    }
}
