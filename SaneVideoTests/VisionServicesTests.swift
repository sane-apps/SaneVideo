//
//  VisionServicesTests.swift
//  SaneVideoTests
//
//  Face tilt feeds smart crop.
//

import CoreGraphics
@testable import SaneVideo
import Testing

@Suite("Vision Services")
struct VisionServicesTests {
    private func face(leftEye: CGPoint?, rightEye: CGPoint?) -> FaceDetection {
        FaceDetection(
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
            confidence: 0.9,
            leftEye: leftEye,
            rightEye: rightEye,
            nose: nil,
            mouth: nil
        )
    }

    @Test("Face angle is 0 for level eyes and pi/4 for eyes tilted 45 degrees")
    func faceAngleFromEyes() throws {
        let level = face(leftEye: CGPoint(x: 0.35, y: 0.5), rightEye: CGPoint(x: 0.65, y: 0.5))
        let tilted = face(leftEye: CGPoint(x: 0.4, y: 0.4), rightEye: CGPoint(x: 0.6, y: 0.6))

        #expect(try abs(#require(level.faceAngle)) < 0.001)
        #expect(try abs(#require(tilted.faceAngle) - .pi / 4) < 0.001)
    }

    @Test("Face angle is nil without both eyes")
    func faceAngleNilWithoutEyes() {
        #expect(face(leftEye: nil, rightEye: nil).faceAngle == nil)
        #expect(face(leftEye: CGPoint(x: 0.4, y: 0.5), rightEye: nil).faceAngle == nil)
    }
}
