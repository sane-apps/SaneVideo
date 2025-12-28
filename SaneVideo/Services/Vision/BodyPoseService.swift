//
//  BodyPoseService.swift
//  SaneVideo
//
//  Apple Vision framework for human body and hand pose detection
//  Tracks skeleton, gestures, and hand positions
//

import AVFoundation
import CoreImage
import Foundation
import Vision

/// Detected body pose with joint positions
struct BodyPose: Identifiable, Sendable {
    let id = UUID()
    let joints: [JointName: JointPosition]
    let confidence: Float
    let boundingBox: CGRect

    /// Check if a specific gesture is detected
    nonisolated func isGesture(_ gesture: BodyGesture) -> Bool {
        switch gesture {
        case .handsUp:
            guard let leftWrist = joints[.leftWrist],
                  let rightWrist = joints[.rightWrist],
                  let nose = joints[.nose] else { return false }
            return leftWrist.position.y < nose.position.y && rightWrist.position.y < nose.position.y

        case .armsCrossed:
            guard let leftWrist = joints[.leftWrist],
                  let rightWrist = joints[.rightWrist],
                  let leftShoulder = joints[.leftShoulder],
                  let rightShoulder = joints[.rightShoulder] else { return false }
            // Wrists crossed over chest area
            return leftWrist.position.x > rightShoulder.position.x &&
                rightWrist.position.x < leftShoulder.position.x

        case .waving:
            guard let rightWrist = joints[.rightWrist],
                  let rightElbow = joints[.rightElbow] else { return false }
            return rightWrist.position.y < rightElbow.position.y

        case .pointing:
            guard let rightWrist = joints[.rightWrist],
                  let rightElbow = joints[.rightElbow] else { return false }
            // Arm extended
            let armLength = hypot(
                rightWrist.position.x - rightElbow.position.x,
                rightWrist.position.y - rightElbow.position.y
            )
            return armLength > 0.15
        }
    }
}

/// Joint position with confidence
struct JointPosition: Sendable {
    let position: CGPoint // Normalized 0-1
    let confidence: Float
}

/// Body joint names
enum JointName: String, CaseIterable, Sendable {
    case nose
    case leftEye, rightEye
    case leftEar, rightEar
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case neck
    case root // Center of body

    nonisolated var visionJointName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: return .nose
        case .leftEye: return .leftEye
        case .rightEye: return .rightEye
        case .leftEar: return .leftEar
        case .rightEar: return .rightEar
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        case .neck: return .neck
        case .root: return .root
        }
    }
}

/// Detectable body gestures
enum BodyGesture: String, CaseIterable, Sendable {
    case handsUp = "Hands Up"
    case armsCrossed = "Arms Crossed"
    case waving = "Waving"
    case pointing = "Pointing"
}

/// Detected hand pose
struct HandPose: Identifiable, Sendable {
    let id = UUID()
    let chirality: HandChirality
    let fingers: [FingerName: [JointPosition]]
    let wrist: JointPosition?
    let confidence: Float

    /// Check for common hand gestures
    var gesture: HandGesture? {
        // Count extended fingers
        var extendedCount = 0
        for (finger, joints) in fingers where finger != .thumb {
            if let tip = joints.last, let base = joints.first {
                if tip.position.y < base.position.y - 0.05 {
                    extendedCount += 1
                }
            }
        }

        switch extendedCount {
        case 0: return .fist
        case 1:
            if let indexTip = fingers[.index]?.last, let indexBase = fingers[.index]?.first,
               indexTip.position.y < indexBase.position.y - 0.05 {
                return .pointingUp
            }
            return nil
        case 2: return .peace
        case 5: return .openPalm
        default: return nil
        }
    }
}

enum HandChirality: String, Sendable {
    case left, right
}

enum FingerName: String, CaseIterable, Sendable {
    case thumb, index, middle, ring, little
}

enum HandGesture: String, Sendable {
    case fist = "Fist"
    case openPalm = "Open Palm"
    case peace = "Peace"
    case pointingUp = "Pointing Up"
    case thumbsUp = "Thumbs Up"
}

/// Service for detecting body and hand poses
/// Note: Does not conform to BodyPoseServiceProtocol due to Swift 6 actor isolation rules.
actor BodyPoseService {

    init() {}

    /// Detect all body poses in an image
    func detectBodyPoses(in image: CIImage) async throws -> [BodyPose] {
        let request = VNDetectHumanBodyPoseRequest()

        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        return observations.compactMap { observation -> BodyPose? in
            var joints: [JointName: JointPosition] = [:]

            for jointName in JointName.allCases {
                if let point = try? observation.recognizedPoint(jointName.visionJointName),
                   point.confidence > 0.3 {
                    joints[jointName] = JointPosition(
                        position: CGPoint(x: point.location.x, y: 1.0 - point.location.y),
                        confidence: point.confidence
                    )
                }
            }

            guard !joints.isEmpty else { return nil }

            // Calculate bounding box from joints
            let xs = joints.values.map { $0.position.x }
            let ys = joints.values.map { $0.position.y }
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 1
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 1

            return BodyPose(
                joints: joints,
                confidence: observation.confidence,
                boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )
        }
    }

    /// Detect hand poses in an image
    func detectHandPoses(in image: CIImage) async throws -> [HandPose] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        return observations.compactMap { observation -> HandPose? in
            var fingers: [FingerName: [JointPosition]] = [:]

            // Get finger joints
            for finger in FingerName.allCases {
                let jointGroup: VNHumanHandPoseObservation.JointsGroupName
                switch finger {
                case .thumb: jointGroup = .thumb
                case .index: jointGroup = .indexFinger
                case .middle: jointGroup = .middleFinger
                case .ring: jointGroup = .ringFinger
                case .little: jointGroup = .littleFinger
                }

                if let points = try? observation.recognizedPoints(jointGroup) {
                    let jointPositions = points.values
                        .sorted { $0.location.y > $1.location.y }
                        .map { JointPosition(position: CGPoint(x: $0.location.x, y: 1.0 - $0.location.y), confidence: $0.confidence) }
                    if !jointPositions.isEmpty {
                        fingers[finger] = jointPositions
                    }
                }
            }

            // Get wrist
            let wrist: JointPosition?
            if let wristPoint = try? observation.recognizedPoint(.wrist), wristPoint.confidence > 0.3 {
                wrist = JointPosition(
                    position: CGPoint(x: wristPoint.location.x, y: 1.0 - wristPoint.location.y),
                    confidence: wristPoint.confidence
                )
            } else {
                wrist = nil
            }

            guard !fingers.isEmpty else { return nil }

            return HandPose(
                chirality: observation.chirality == .left ? .left : .right,
                fingers: fingers,
                wrist: wrist,
                confidence: observation.confidence
            )
        }
    }

    /// Detect gestures in a video and return timestamps
    /// - Parameters:
    ///   - videoURL: URL of video to analyze
    ///   - gestures: Gestures to detect
    ///   - sampleInterval: Seconds between frame samples
    ///   - progressHandler: Optional callback with (currentFrame, totalFrames)
    func detectGestures(
        in videoURL: URL,
        gestures: [BodyGesture] = BodyGesture.allCases,
        sampleInterval: TimeInterval = 0.5,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [(gesture: BodyGesture, time: CMTime)] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalFrames = Int(duration.seconds / sampleInterval)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        var detectedGestures: [(BodyGesture, CMTime)] = []
        var currentTime = CMTime.zero
        var frameIndex = 0

        await MainActor.run {
            AppLogger.vision.info("🕺 Scanning \(totalFrames) frames for gestures...")
        }

        while currentTime < duration {
            frameIndex += 1
            progressHandler?(frameIndex, totalFrames)

            do {
                let (cgImage, actualTime) = try await generator.image(at: currentTime)
                let ciImage = CIImage(cgImage: cgImage)
                let poses = try await detectBodyPoses(in: ciImage)

                for pose in poses {
                    for gesture in gestures where pose.isGesture(gesture) {
                        detectedGestures.append((gesture, actualTime))
                    }
                }
            } catch {
                // Skip this frame
            }

            currentTime = currentTime + CMTime(seconds: sampleInterval, preferredTimescale: 600)
        }

        return detectedGestures
    }
}
