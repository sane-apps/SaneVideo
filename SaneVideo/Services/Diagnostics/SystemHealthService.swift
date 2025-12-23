//
//  SystemHealthService.swift
//  SaneVideo
//
//  Monitors system health and provides proactive warnings
//

import Foundation

@MainActor
@Observable
class SystemHealthService {
    
    enum HealthStatus {
        case excellent
        case good
        case fair
        case poor
        case critical
    }
    
    struct HealthCheck {
        let status: HealthStatus
        let message: String
        let suggestions: [String]
    }
    
    private(set) var currentHealth: HealthCheck?
    private(set) var diskSpaceGB: Double = 0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var memoryPressure: Bool = false
    
    init() {
        updateHealth()
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Monitor thermal state
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateHealth()
        }
        
        // Periodic health checks
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHealth()
            }
        }
    }
    
    func updateHealth() {
        // Check disk space
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attributes[.systemFreeSize] as? Int64 {
            diskSpaceGB = Double(freeSpace) / 1_000_000_000.0
        }
        
        // Check thermal state
        thermalState = ProcessInfo.processInfo.thermalState
        
        // Check memory pressure (simplified)
        memoryPressure = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        
        // Determine overall health
        currentHealth = calculateHealth()
    }
    
    private func calculateHealth() -> HealthCheck {
        var issues: [String] = []
        var suggestions: [String] = []
        var status: HealthStatus = .excellent
        
        // Disk space check
        if diskSpaceGB < 1.0 {
            status = .critical
            issues.append("Critical: Less than 1GB free disk space")
            suggestions.append("Free up disk space before exporting")
        } else if diskSpaceGB < 5.0 {
            status = status == .excellent ? .good : status
            issues.append("Warning: Less than 5GB free disk space")
            suggestions.append("Consider freeing up space for large exports")
        }
        
        // Thermal state check
        switch thermalState {
        case .critical:
            status = .critical
            issues.append("Critical: System overheating")
            suggestions.append("Close other apps and let system cool down")
        case .serious:
            status = status == .excellent ? .fair : status
            issues.append("Warning: High thermal pressure")
            suggestions.append("System may throttle performance")
        case .fair:
            status = status == .excellent ? .good : status
        case .nominal:
            break
        @unknown default:
            break
        }
        
        // Memory pressure
        if memoryPressure {
            status = status == .excellent ? .good : status
            issues.append("System under memory pressure")
            suggestions.append("Close unused apps for better performance")
        }
        
        let message: String
        if issues.isEmpty {
            message = "System health: Excellent ✅"
        } else {
            message = issues.joined(separator: ". ")
        }
        
        return HealthCheck(
            status: status,
            message: message,
            suggestions: suggestions
        )
    }
    
    /// Get export quality recommendation based on system health
    func getRecommendedExportSettings() -> SaneExportSettings.ExportResolution {
        switch currentHealth?.status {
        case .excellent, .good:
            return .uhd4K
        case .fair:
            return .hd1080
        case .poor, .critical:
            return .hd720
        case .none:
            return .hd1080
        }
    }
}

