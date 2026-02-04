//
//  SpringMassDamperSimulationTests.swift
//  SaneVideoTests
//
//  Tests for spring-mass-damper physics simulation
//

import Testing
import simd

@testable import SaneVideo

struct SpringMassDamperSimulationTests {

    // MARK: - Basic Convergence

    @Test("Spring converges to target from rest")
    func convergesToTarget() {
        var spring = SpringMassDamperSimulation(
            position: SIMD2(0, 0),
            target: SIMD2(1, 1),
            profile: .default
        )

        // Run simulation for 2 seconds at 60fps
        for _ in 0 ..< 120 {
            spring.step(dt: 1.0 / 60.0)
        }

        #expect(spring.isSettled)
        #expect(abs(spring.position.x - 1.0) < 0.01)
        #expect(abs(spring.position.y - 1.0) < 0.01)
    }

    @Test("Spring converges with 1D convenience")
    func convergesToTarget1D() {
        var spring = SpringMassDamperSimulation(
            value: 0,
            target: 5.0,
            profile: .default
        )

        for _ in 0 ..< 120 {
            spring.step(dt: 1.0 / 60.0)
        }

        #expect(spring.isSettled)
        #expect(abs(spring.value - 5.0) < 0.01)
    }

    // MARK: - Profile Behavior

    @Test("Snappy profile settles faster than default")
    func snappyFasterThanDefault() {
        var snappy = SpringMassDamperSimulation(
            value: 0, target: 1.0, profile: .snappy
        )
        var normal = SpringMassDamperSimulation(
            value: 0, target: 1.0, profile: .default
        )

        // Run both for 30 frames (0.5s)
        for _ in 0 ..< 30 {
            snappy.step(dt: 1.0 / 60.0)
            normal.step(dt: 1.0 / 60.0)
        }

        // Snappy should be closer to target after same time
        let snappyDist = abs(snappy.value - 1.0)
        let normalDist = abs(normal.value - 1.0)
        #expect(snappyDist < normalDist)
    }

    @Test("Drag profile is heavier than default")
    func dragSlowerThanDefault() {
        var drag = SpringMassDamperSimulation(
            value: 0, target: 1.0, profile: .drag
        )
        var normal = SpringMassDamperSimulation(
            value: 0, target: 1.0, profile: .default
        )

        // Run both for 15 frames (0.25s)
        for _ in 0 ..< 15 {
            drag.step(dt: 1.0 / 60.0)
            normal.step(dt: 1.0 / 60.0)
        }

        // Drag should be further from target (slower response)
        let dragDist = abs(drag.value - 1.0)
        let normalDist = abs(normal.value - 1.0)
        #expect(dragDist > normalDist)
    }

    @Test("Zoom profile converges smoothly")
    func zoomProfileConverges() {
        var spring = SpringMassDamperSimulation(
            value: 1.0, target: 1.5, profile: .zoom
        )

        for _ in 0 ..< 180 {
            spring.step(dt: 1.0 / 60.0)
        }

        #expect(spring.isSettled)
        #expect(abs(spring.value - 1.5) < 0.01)
    }

    @Test("Custom profile parameters are respected")
    func customProfileWorks() {
        let expectedStiffness = 500.0
        let expectedDamping = 50.0
        let expectedMass = 1.0
        let profile = SpringMassDamperSimulation.Profile.custom(
            stiffness: expectedStiffness,
            damping: expectedDamping,
            mass: expectedMass
        )
        #expect(profile.stiffness == expectedStiffness)
        #expect(profile.damping == expectedDamping)
        #expect(profile.mass == expectedMass)

        var spring = SpringMassDamperSimulation(
            value: 0, target: 1.0, profile: profile
        )

        // Very stiff spring should converge quickly
        for _ in 0 ..< 60 {
            spring.step(dt: 1.0 / 60.0)
        }

        #expect(spring.isSettled)
    }

    // MARK: - Stability

    @Test("Large dt is clamped to prevent explosion")
    func largeDtClamped() {
        var spring = SpringMassDamperSimulation(
            value: 0, target: 1.0, profile: .default
        )

        // Pass absurdly large dt
        spring.step(dt: 10.0)

        // Should not explode — position should be finite
        #expect(spring.position.x.isFinite)
        #expect(spring.position.y.isFinite)
        #expect(spring.velocity.x.isFinite)
        #expect(spring.velocity.y.isFinite)
    }

    @Test("Zero dt is a no-op")
    func zeroDtNoOp() {
        var spring = SpringMassDamperSimulation(
            position: SIMD2(0.5, 0.5),
            target: SIMD2(1.0, 1.0),
            profile: .default
        )

        let posBefore = spring.position
        spring.step(dt: 0)

        #expect(spring.position == posBefore)
    }

    @Test("Negative dt is clamped to zero")
    func negativeDtClamped() {
        var spring = SpringMassDamperSimulation(
            position: SIMD2(0.5, 0.5),
            target: SIMD2(1.0, 1.0),
            profile: .default
        )

        let posBefore = spring.position
        spring.step(dt: -1.0)

        #expect(spring.position == posBefore)
    }

    // MARK: - Settlement

    @Test("Spring at target with zero velocity is settled")
    func settledWhenAtTarget() {
        let spring = SpringMassDamperSimulation(
            position: SIMD2(1.0, 1.0),
            velocity: .zero,
            target: SIMD2(1.0, 1.0),
            profile: .default
        )

        #expect(spring.isSettled)
    }

    @Test("Spring far from target is not settled")
    func notSettledWhenFar() {
        let spring = SpringMassDamperSimulation(
            position: SIMD2(0, 0),
            target: SIMD2(1.0, 1.0),
            profile: .default
        )

        #expect(!spring.isSettled)
    }

    // MARK: - Control Methods

    @Test("snapToTarget sets position and zeros velocity")
    func snapToTargetWorks() {
        var spring = SpringMassDamperSimulation(
            position: SIMD2(0, 0),
            velocity: SIMD2(5, 5),
            target: SIMD2(3, 4),
            profile: .default
        )

        spring.snapToTarget()

        #expect(spring.position == SIMD2(3, 4))
        #expect(spring.velocity == .zero)
        #expect(spring.isSettled)
    }

    @Test("reset sets position, velocity, and target")
    func resetWorks() {
        var spring = SpringMassDamperSimulation(
            position: SIMD2(1, 1),
            velocity: SIMD2(5, 5),
            target: SIMD2(10, 10),
            profile: .default
        )

        spring.reset(to: SIMD2(2, 3))

        #expect(spring.position == SIMD2(2, 3))
        #expect(spring.velocity == .zero)
        #expect(spring.target == SIMD2(2, 3))
        #expect(spring.isSettled)
    }

    @Test("step(toward:dt:) updates target and advances")
    func stepTowardWorks() {
        var spring = SpringMassDamperSimulation(
            value: 0, target: 0, profile: .default
        )

        spring.step(toward: 1.0, dt: 1.0 / 60.0)

        // Should have moved toward target
        #expect(spring.target.x == 1.0)
        #expect(spring.value > 0)
    }

    // MARK: - 2D Motion

    @Test("2D diagonal motion converges correctly")
    func diagonalMotion() {
        var spring = SpringMassDamperSimulation(
            position: SIMD2(0, 0),
            target: SIMD2(3, 4),
            profile: .default
        )

        for _ in 0 ..< 180 {
            spring.step(dt: 1.0 / 60.0)
        }

        #expect(spring.isSettled)
        #expect(abs(spring.position.x - 3.0) < 0.01)
        #expect(abs(spring.position.y - 4.0) < 0.01)
    }
}
