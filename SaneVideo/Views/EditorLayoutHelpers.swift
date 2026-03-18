//
//  EditorLayoutHelpers.swift
//  SaneVideo
//
//  Extracted from EditorLayoutView.swift to reduce file size
//  Contains: VideoDisplayMode, GridPattern, CollapseButton, TimelineKeyboardModifier
//

import SwiftUI

// MARK: - Video Display Modes

enum VideoDisplayMode: String, CaseIterable {
    case fit      // Fit entire video (may have letterboxing)
    case fill     // Fill container (may crop edges)
    case actual   // Actual size (1:1 pixels, scrollable if larger)

    var label: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .actual: return "Actual Size"
        }
    }

    var icon: String {
        switch self {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .actual: return "1.square"
        }
    }
}

// MARK: - Grid Pattern Shape

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 40

        for x in stride(from: 0, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }

        for y in stride(from: 0, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }

        return path
    }
}

// MARK: - Collapse Button

struct CollapseButton: View {
    @Binding var isCollapsed: Bool
    let edge: HorizontalEdge

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: chevronName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 16, height: 44)
                .background(Theme.Colors.editorPanelElevated)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? String(localized: "action.show_panel", defaultValue: "Show Panel") : String(localized: "action.hide_panel", defaultValue: "Hide Panel"))
    }

    private var chevronName: String {
        switch edge {
        case .leading:
            return isCollapsed ? "chevron.right" : "chevron.left"
        case .trailing:
            return isCollapsed ? "chevron.left" : "chevron.right"
        }
    }
}

// MARK: - Timeline Keyboard Modifier
// Extracted to help compiler type-check the complex EditorLayoutView body

struct TimelineKeyboardModifier: ViewModifier {
    @Environment(AppState.self) var appState

    // J/K/L shuttle rate tracking (stacks: 1x → 2x → 4x)
    @State private var shuttleRate: Float = 1.0

    let onPrevBoundary: () -> Void
    let onNextBoundary: () -> Void
    let onExtendPrev: () -> Void
    let onExtendNext: () -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onSelectAtPlayhead: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            // Up Arrow: Shift = extend selection, plain = previous boundary
            .onKeyPress(.upArrow, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    onExtendPrev()
                } else {
                    onPrevBoundary()
                }
                return .handled
            }
            // Down Arrow: Shift = extend selection, plain = next boundary
            .onKeyPress(.downArrow, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    onExtendNext()
                } else {
                    onNextBoundary()
                }
                return .handled
            }
            // Left Arrow: Shift = 10s back, plain = frame back (2026-01-01)
            .onKeyPress(.leftArrow, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    appState.playbackState.seekBackward10Seconds()
                } else {
                    appState.playbackState.stepBackward()
                }
                return .handled
            }
            // Right Arrow: Shift = 10s forward, plain = frame forward (2026-01-01)
            .onKeyPress(.rightArrow, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    appState.playbackState.seekForward10Seconds()
                } else {
                    appState.playbackState.stepForward()
                }
                return .handled
            }
            // Cmd+A = select all
            .onKeyPress(KeyEquivalent("a"), phases: .down) { press in
                if press.modifiers.contains(.command) {
                    onSelectAll()
                    return .handled
                }
                return .ignored
            }
            // Escape = deselect all
            .onKeyPress(.escape) {
                onDeselectAll()
                return .handled
            }
            // D = select clip at playhead
            .onKeyPress(KeyEquivalent("d")) {
                onSelectAtPlayhead()
                return .handled
            }
            // J = Shuttle backward (stack: -1x → -2x → -4x) (2026-01-01)
            .onKeyPress(KeyEquivalent("j")) {
                if shuttleRate > 0 {
                    shuttleRate = -1.0
                } else {
                    shuttleRate = max(-4.0, shuttleRate * 2)
                }
                appState.playbackState.setPlaybackRate(shuttleRate)
                return .handled
            }
            // K = Pause (2026-01-01)
            .onKeyPress(KeyEquivalent("k")) {
                shuttleRate = 1.0 // Reset for next J/L press
                appState.playbackState.pause()
                return .handled
            }
            // L = Shuttle forward (stack: 1x → 2x → 4x) (2026-01-01)
            .onKeyPress(KeyEquivalent("l")) {
                if shuttleRate <= 0 {
                    shuttleRate = 1.0
                } else {
                    shuttleRate = min(4.0, shuttleRate * 2)
                }
                appState.playbackState.setPlaybackRate(shuttleRate)
                return .handled
            }
    }
}
