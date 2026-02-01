//
//  SpringMassDamperSimulation.swift
//  SaneVideo
//
//  Spring-mass-damper physics simulation for natural animation transitions.
//  Inspired by Cap's zoom interpolation (PR #1504).
//
//  Physics: acceleration = (stiffness * (target - position) - damping * velocity) / mass
//  Integration: Semi-implicit Euler (velocity first, then position)
//

import Foundation
import simd

/// Spring-mass-damper physics simulation for 2D animation.
///
/// Produces natural-feeling motion by simulating a damped spring system.
/// Used for cursor smoothing, zoom transitions, and viewport following.
struct SpringMassDamperSimulation: Sendable {

    // MARK: - Profile

    /// Predefined spring profiles for different animation contexts
    enum Profile: Sendable {
        /// General-purpose smooth motion (stiffness=170, damping=26, mass=1.0)
        case `default`
        /// Snappy response near clicks (stiffness=300, damping=30, mass=0.8)
        case snappy
        /// Heavy feel during drag operations (stiffness=120, damping=20, mass=1.2)
        case drag
        /// Zoom scale transitions (stiffness=200, damping=40, mass=2.25)
        case zoom
        /// Custom parameters
        case custom(stiffness: Double, damping: Double, mass: Double)

        var stiffness: Double {
            switch self {
            case .default: return 170
            case .snappy: return 300
            case .drag: return 120
            case .zoom: return 200
            case .custom(let s, _, _): return s
            }
        }

        var damping: Double {
            switch self {
            case .default: return 26
            case .snappy: return 30
            case .drag: return 20
            case .zoom: return 40
            case .custom(_, let d, _): return d
            }
        }

        var mass: Double {
            switch self {
            case .default: return 1.0
            case .snappy: return 0.8
            case .drag: return 1.2
            case .zoom: return 2.25
            case .custom(_, _, let m): return m
            }
        }
    }

    // MARK: - State

    /// Current position in 2D space
    private(set) var position: SIMD2<Double>

    /// Current velocity in 2D space
    private(set) var velocity: SIMD2<Double>

    /// Target position the spring is pulling toward
    var target: SIMD2<Double>

    /// Active spring profile
    var profile: Profile

    // MARK: - Settlement thresholds

    /// Position must be within this distance of target to be considered settled
    static let positionThreshold: Double = 0.0005

    /// Velocity must be below this magnitude to be considered settled
    static let velocityThreshold: Double = 0.001

    // MARK: - Initialization

    init(
        position: SIMD2<Double> = .zero,
        velocity: SIMD2<Double> = .zero,
        target: SIMD2<Double> = .zero,
        profile: Profile = .default
    ) {
        self.position = position
        self.velocity = velocity
        self.target = target
        self.profile = profile
    }

    /// Convenience initializer for 1D simulation
    init(
        value: Double = 0,
        velocity: Double = 0,
        target: Double = 0,
        profile: Profile = .default
    ) {
        self.position = SIMD2(value, 0)
        self.velocity = SIMD2(velocity, 0)
        self.target = SIMD2(target, 0)
        self.profile = profile
    }

    // MARK: - Simulation

    /// Advance the simulation by `dt` seconds using semi-implicit Euler integration.
    ///
    /// Semi-implicit Euler updates velocity first, then uses the new velocity to update position.
    /// This is more stable than explicit Euler for spring systems.
    ///
    /// - Parameter dt: Time step in seconds. Clamped to [0, 0.1] to prevent instability.
    mutating func step(dt: Double) {
        let clampedDt = min(max(dt, 0), 0.1) // Prevent explosion from huge dt
        guard clampedDt > 0 else { return }

        let stiffness = profile.stiffness
        let damping = profile.damping
        let mass = profile.mass
        guard mass > 0 else { return }

        // Spring force: F = stiffness * (target - position) - damping * velocity
        let displacement = target - position
        let springForce = stiffness * displacement
        let dampingForce = damping * velocity
        let acceleration = (springForce - dampingForce) / mass

        // Semi-implicit Euler: update velocity first, then position
        velocity = velocity + acceleration * clampedDt
        position = position + velocity * clampedDt
    }

    /// Advance the simulation toward a specific target.
    ///
    /// Convenience method that sets the target then steps.
    mutating func step(toward newTarget: SIMD2<Double>, dt: Double) {
        target = newTarget
        step(dt: dt)
    }

    /// Convenience for 1D step
    mutating func step(toward value: Double, dt: Double) {
        step(toward: SIMD2(value, 0), dt: dt)
    }

    /// Whether the simulation has settled (close enough to target with low velocity)
    var isSettled: Bool {
        let displacement = simd_length(target - position)
        let speed = simd_length(velocity)
        return displacement < Self.positionThreshold && speed < Self.velocityThreshold
    }

    /// Current 1D value (x component) for single-axis usage
    var value: Double {
        position.x
    }

    /// Snap directly to target, zeroing velocity
    mutating func snapToTarget() {
        position = target
        velocity = .zero
    }

    /// Reset to a specific position with zero velocity
    mutating func reset(to newPosition: SIMD2<Double>) {
        position = newPosition
        velocity = .zero
        target = newPosition
    }
}
