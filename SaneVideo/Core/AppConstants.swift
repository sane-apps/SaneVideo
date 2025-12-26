//
//  AppConstants.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreGraphics
import Foundation

enum AppConstants {
    // MARK: - Timeline

    static let timelineHeight: CGFloat = 120 // Optimized for screen real estate (was 200)
    static let pixelsPerSecond: CGFloat = 50.0

    // MARK: - UI

    static let defaultWindowWidth: CGFloat = 1400
    static let defaultWindowHeight: CGFloat = 900

    // MARK: - Timing (Nanoseconds)

    enum Timing {
        /// Small delay for UI sync (50ms)
        static let uiSync: UInt64 = 50_000_000

        /// Standard async delay (100ms)
        static let standard: UInt64 = 100_000_000

        /// Window animation completion delay (150ms)
        static let windowAnimation: UInt64 = 150_000_000

        /// Camera stabilization delay (200ms)
        static let cameraStabilization: UInt64 = 200_000_000

        /// SwiftUI teardown delay (300ms)
        static let swiftUITeardown: UInt64 = 300_000_000

        /// Camera switch timeout (10s)
        static let cameraSwitchTimeout: UInt64 = 10_000_000_000

        /// Screen picker timeout (120s / 2 minutes - user interaction required)
        static let screenPickerTimeout: UInt64 = 120_000_000_000

        /// Filter staleness threshold (5 minutes)
        static let filterStalenessThreshold: TimeInterval = 300

        /// Source switch polling interval (100ms)
        static let switchPollingInterval: UInt64 = 100_000_000

        /// Max source switch polling attempts (50 = 5 seconds)
        static let maxSwitchPollingAttempts = 50
    }
}
