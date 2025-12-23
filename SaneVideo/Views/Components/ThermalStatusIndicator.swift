//
//  ThermalStatusIndicator.swift
//  SaneVideo
//
//  Enhanced thermal status indicator with clear messaging
//

import SwiftUI

/// Enhanced thermal status indicator with user-friendly messaging
struct ThermalStatusIndicator: View {
    @State private var thermalState: ProcessInfo.ThermalState = .nominal
    @State private var isThrottled: Bool = false
    
    var body: some View {
        if ThermalManager.shared.isThermalPressureHigh {
            HStack(spacing: 8) {
                Image(systemName: thermalIcon)
                    .font(.caption)
                    .foregroundColor(thermalColor)
                    .symbolEffect(.pulse, options: .repeating)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(thermalTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(thermalMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(thermalColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(thermalColor.opacity(0.3), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                updateThermalState()
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                updateThermalState()
            }
        }
    }
    
    private var thermalIcon: String {
        switch performanceLevel {
        case .emergency:
            return "thermometer.sun.fill"
        case .throttled:
            return "thermometer.medium"
        default:
            return "thermometer"
        }
    }
    
    private var thermalColor: Color {
        switch performanceLevel {
        case .emergency:
            return .red
        case .throttled:
            return .orange
        default:
            return .yellow
        }
    }
    
    private var thermalTitle: String {
        switch performanceLevel {
        case .emergency:
            return "System Overheating"
        case .throttled:
            return "Optimizing Performance"
        default:
            return "System Warm"
        }
    }
    
    private var thermalMessage: String {
        switch performanceLevel {
        case .emergency:
            return "Performance reduced to protect your Mac. Export may be slower."
        case .throttled:
            return "SaneVideo is optimizing to prevent overheating. Your Mac is safe."
        default:
            return "Monitoring system temperature"
        }
    }
    
    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
        performanceLevel = ThermalManager.shared.performanceLevel
    }
}

/// Compact thermal indicator for status bar
struct CompactThermalIndicator: View {
    var body: some View {
        if ThermalManager.shared.isThermalPressureHigh {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Optimizing")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.1))
            )
        }
    }
}

