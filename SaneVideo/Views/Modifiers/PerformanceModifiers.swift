//
//  PerformanceModifiers.swift
//  SaneVideo
//
//  Performance optimization modifiers to reduce unnecessary re-renders
//

import SwiftUI

/// ViewModifier that debounces value changes to reduce re-renders
struct DebouncedChangeModifier<T: Equatable>: ViewModifier {
    let value: T
    let delay: TimeInterval
    let action: (T) -> Void
    
    @State private var debouncedValue: T
    @State private var task: Task<Void, Never>?
    
    init(value: T, delay: TimeInterval = 0.3, action: @escaping (T) -> Void) {
        self.value = value
        self.delay = delay
        self.action = action
        _debouncedValue = State(initialValue: value)
    }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, newValue in
                task?.cancel()
                task = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    if !Task.isCancelled {
                        await MainActor.run {
                            debouncedValue = newValue
                            action(newValue)
                        }
                    }
                }
            }
    }
}

/// ViewModifier that throttles value changes
struct ThrottledChangeModifier<T: Equatable>: ViewModifier {
    let value: T
    let interval: TimeInterval
    let action: (T) -> Void
    
    @State private var lastUpdateTime: Date = .distantPast
    
    init(value: T, interval: TimeInterval = 0.1, action: @escaping (T) -> Void) {
        self.value = value
        self.interval = interval
        self.action = action
    }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, newValue in
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= interval {
                    lastUpdateTime = now
                    action(newValue)
                }
            }
    }
}

/// ViewModifier that only updates when value actually changes (deep equality)
struct EquatableChangeModifier<T: Equatable>: ViewModifier {
    let value: T
    let action: (T) -> Void
    
    @State private var lastValue: T?
    
    init(value: T, action: @escaping (T) -> Void) {
        self.value = value
        self.action = action
    }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, newValue in
                if lastValue != newValue {
                    lastValue = newValue
                    action(newValue)
                }
            }
    }
}

// Removed ConditionalRenderModifier - not needed for current implementation

extension View {
    /// Debounces value changes
    func debounceChange<T: Equatable>(
        of value: T,
        delay: TimeInterval = 0.3,
        action: @escaping (T) -> Void
    ) -> some View {
        modifier(DebouncedChangeModifier(value: value, delay: delay, action: action))
    }
    
    /// Throttles value changes
    func throttleChange<T: Equatable>(
        of value: T,
        interval: TimeInterval = 0.1,
        action: @escaping (T) -> Void
    ) -> some View {
        modifier(ThrottledChangeModifier(value: value, interval: interval, action: action))
    }
    
    /// Only triggers on actual value changes
    func onChangeIfDifferent<T: Equatable>(
        of value: T,
        action: @escaping (T) -> Void
    ) -> some View {
        modifier(EquatableChangeModifier(value: value, action: action))
    }
}
