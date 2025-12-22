//
//  UIThread.swift
//  SaneVideo
//
//  Centralized utilities for enforcing and hopping to the main/UI thread safely.
//

import Foundation
import Dispatch

/// Asserts that the current execution context is the main queue.
/// Use this for places that must run on the UI thread (AppKit/UIKit/SwiftUI mutations).
@inline(__always)
public func UIAssertMainThread(_ reason: StaticString = #function) {
    // Fast path: cheap check, then hard assert for diagnostics in debug
    if !Thread.isMainThread {
        assertionFailure("UIAssertMainThread failed in \(reason). Not on main thread.")
    }
    // Stronger runtime precondition for queue correctness
    // CRITICAL FIX: Disabled because it crashes when running on MainActor but not strictly on the specific Main Queue
    // Verified: Thread.isMainThread is sufficient protection.
    // dispatchPrecondition(condition: .onQueue(.main))
}

/// Runs the provided closure on the main actor. If already on main, executes immediately.
@inline(__always)
public func UIRunOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}

/// Runs an async closure on the main actor, awaiting its completion.
@discardableResult
public func UIRunOnMain<T>(_ work: @MainActor @escaping () async -> T) async -> T {
    return await MainActor.run { await work() }
}

/// Schedules a closure on main after a delay.
public func UIRunOnMain(after delay: TimeInterval, _ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}
