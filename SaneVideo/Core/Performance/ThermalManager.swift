//
//  ThermalManager.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import Foundation
import SwiftUI
import Observation

/// Performance levels based on thermal state.
enum PerformanceLevel: String, CaseIterable, Sendable {
    case high        // Thermal state: nominal
    case balanced    // Thermal state: fair
    case throttled   // Thermal state: serious
    case emergency   // Thermal state: critical
}

/// Manages and monitors the system's thermal state to optimize application performance.
@MainActor
@Observable
final class ThermalManager {
    /// Shared singleton instance.
    static let shared = ThermalManager()
    
    /// The current raw thermal state of the system observed for UI.
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    
    /// The suggested performance level based on current thermal conditions.
    var performanceLevel: PerformanceLevel {
        Self.performanceLevel(for: thermalState)
    }
    
    /// Whether the system is currently under heavy thermal pressure.
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
