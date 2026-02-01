//
//  Keyframe.swift
//  SaneVideo
//
//  Keyframe animation system for animating clip properties over time
//

import CoreMedia
import Foundation

/// Properties that can be animated via keyframes
enum AnimatableProperty: String, Codable, CaseIterable, Sendable {
    case positionX
    case positionY
    case scale
    case rotation
    case opacity
    case volume

    var displayName: String {
        switch self {
        case .positionX: return "Position X"
        case .positionY: return "Position Y"
        case .scale: return "Scale"
        case .rotation: return "Rotation"
        case .opacity: return "Opacity"
        case .volume: return "Volume"
        }
    }

    var defaultValue: Double {
        switch self {
        case .positionX, .positionY: return 0.0
        case .scale: return 1.0
        case .rotation: return 0.0
        case .opacity: return 1.0
        case .volume: return 1.0
        }
    }

    var valueRange: ClosedRange<Double> {
        switch self {
        case .positionX, .positionY: return -1000 ... 1000
        case .scale: return 0.1 ... 3.0
        case .rotation: return 0 ... 360
        case .opacity, .volume: return 0 ... 1
        }
    }
}

/// Easing functions for keyframe interpolation
enum EasingType: String, Codable, CaseIterable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case spring
    /// Physics-based spring using SpringMassDamperSimulation (pre-baked into keyframes)
    case springPhysics

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In/Out"
        case .spring: return "Spring"
        case .springPhysics: return "Spring Physics"
        }
    }

    /// Apply easing function to progress (0.0 to 1.0)
    ///
    /// Note: `.springPhysics` keyframes are pre-baked by `SpringMassDamperSimulation`,
    /// so this method uses linear interpolation between the pre-computed positions.
    func apply(to t: Double) -> Double {
        switch self {
        case .linear, .springPhysics:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .spring:
            // Simple damped spring approximation
            let c4 = (2 * Double.pi) / 3
            return t == 0 ? 0 : t == 1 ? 1 : pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        }
    }
}

/// A single keyframe point
struct Keyframe: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = .init()
    var time: CMTime // Time relative to clip start
    var value: Double // Value at this keyframe
    var easing: EasingType // Easing to NEXT keyframe

    init(time: CMTime, value: Double, easing: EasingType = .easeInOut) {
        self.time = time
        self.value = value
        self.easing = easing
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, timeSeconds, value, easing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let seconds = try container.decode(Double.self, forKey: .timeSeconds)
        time = CMTime(seconds: seconds, preferredTimescale: 600)
        value = try container.decode(Double.self, forKey: .value)
        easing = try container.decode(EasingType.self, forKey: .easing)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time.seconds, forKey: .timeSeconds)
        try container.encode(value, forKey: .value)
        try container.encode(easing, forKey: .easing)
    }
}

/// A track of keyframes for a specific property
struct KeyframeTrack: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = .init()
    var property: AnimatableProperty
    var keyframes: [Keyframe]

    init(property: AnimatableProperty, keyframes: [Keyframe] = []) {
        self.property = property
        self.keyframes = keyframes
    }

    /// Get interpolated value at given time
    func value(at time: CMTime) -> Double {
        // Sort keyframes by time
        let sorted = keyframes.sorted { $0.time < $1.time }

        guard !sorted.isEmpty else {
            return property.defaultValue
        }

        // Before first keyframe
        if time <= sorted[0].time {
            return sorted[0].value
        }

        // After last keyframe
        if time >= sorted[sorted.count - 1].time {
            return sorted[sorted.count - 1].value
        }

        // Find surrounding keyframes
        for i in 0 ..< sorted.count - 1 {
            let k1 = sorted[i]
            let k2 = sorted[i + 1]

            if time >= k1.time && time <= k2.time {
                // Interpolate between k1 and k2
                let totalDuration = k2.time.seconds - k1.time.seconds
                guard totalDuration > 0 else { return k1.value }

                let elapsed = time.seconds - k1.time.seconds
                let linearProgress = elapsed / totalDuration
                let easedProgress = k1.easing.apply(to: linearProgress)

                return k1.value + (k2.value - k1.value) * easedProgress
            }
        }

        return property.defaultValue
    }

    /// Add or update a keyframe at the given time
    mutating func setKeyframe(at time: CMTime, value: Double, easing: EasingType = .easeInOut) {
        // Check if keyframe exists at this time (within small tolerance)
        if let index = keyframes.firstIndex(where: { abs($0.time.seconds - time.seconds) < 0.01 }) {
            keyframes[index].value = value
            keyframes[index].easing = easing
        } else {
            let newKeyframe = Keyframe(time: time, value: value, easing: easing)
            keyframes.append(newKeyframe)
        }
    }

    /// Remove keyframe at given time
    mutating func removeKeyframe(at time: CMTime) {
        keyframes.removeAll { abs($0.time.seconds - time.seconds) < 0.01 }
    }
}

/// Container for all keyframe tracks on a clip
struct KeyframeAnimation: Codable, Equatable, Sendable {
    var tracks: [KeyframeTrack]

    init(tracks: [KeyframeTrack] = []) {
        self.tracks = tracks
    }

    /// Get or create track for a property
    mutating func track(for property: AnimatableProperty) -> KeyframeTrack {
        if let existing = tracks.first(where: { $0.property == property }) {
            return existing
        }
        let newTrack = KeyframeTrack(property: property)
        tracks.append(newTrack)
        return newTrack
    }

    /// Get value for a property at a given time
    func value(for property: AnimatableProperty, at time: CMTime) -> Double {
        if let track = tracks.first(where: { $0.property == property }) {
            return track.value(at: time)
        }
        return property.defaultValue
    }

    /// Set a keyframe for a property
    mutating func setKeyframe(property: AnimatableProperty, at time: CMTime, value: Double, easing: EasingType = .easeInOut) {
        if let index = tracks.firstIndex(where: { $0.property == property }) {
            tracks[index].setKeyframe(at: time, value: value, easing: easing)
        } else {
            var newTrack = KeyframeTrack(property: property)
            newTrack.setKeyframe(at: time, value: value, easing: easing)
            tracks.append(newTrack)
        }
    }

    /// Check if animation has any keyframes
    var isEmpty: Bool {
        tracks.allSatisfy { $0.keyframes.isEmpty }
    }

    /// Access track for property
    subscript(_ property: AnimatableProperty) -> KeyframeTrack? {
        get {
            tracks.first(where: { $0.property == property })
        }
        set {
            if let index = tracks.firstIndex(where: { $0.property == property }) {
                if let newValue {
                    tracks[index] = newValue
                } else {
                    tracks.remove(at: index)
                }
            } else if let newValue {
                tracks.append(newValue)
            }
        }
    }
}
