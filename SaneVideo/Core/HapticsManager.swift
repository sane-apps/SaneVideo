//
//  HapticsManager.swift
//  SaneVideo
//
//  Centralized haptic feedback for macOS trackpad
//

import AppKit

/// Centralized manager for haptic feedback on macOS
/// Uses NSHapticFeedbackManager for Force Touch trackpad feedback
@MainActor
final class HapticsManager {
    private let performer = NSHapticFeedbackManager.defaultPerformer

    init() {}

    // MARK: - Standard Patterns

    /// Light tap for selection changes, toggles
    func selection() {
        performer.perform(.generic, performanceTime: .default)
    }

    /// Medium tap for button presses, confirmations
    func impact() {
        performer.perform(.alignment, performanceTime: .default)
    }

    /// Strong tap for snapping, important events
    func snap() {
        performer.perform(.levelChange, performanceTime: .default)
    }

    /// Success feedback for completed actions
    func success() {
        // Double tap pattern for success
        performer.perform(.alignment, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.performer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Warning feedback for errors or destructive actions
    func warning() {
        performer.perform(.levelChange, performanceTime: .now)
    }
}
