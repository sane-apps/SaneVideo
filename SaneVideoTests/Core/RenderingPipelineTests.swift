
import XCTest
import CoreMedia
import CoreImage
@testable import SaneVideo

/// Tests for the rendering pipeline: Effects, Keyframes, and Transitions
class RenderingPipelineTests: XCTestCase {
    
    // MARK: - Keyframe Tests
    
    func testKeyframeInterpolationLinear() {
        // Create a keyframe track with linear interpolation
        var track = KeyframeTrack(property: .opacity)
        track.keyframes = [
            Keyframe(time: .zero, value: 0.0, easing: .linear),
            Keyframe(time: CMTime(seconds: 1.0, preferredTimescale: 600), value: 1.0, easing: .linear)
        ]
        
        // Test midpoint interpolation
        let midValue = track.value(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        XCTAssertEqual(midValue, 0.5, accuracy: 0.01, "Linear interpolation at 50% should be 0.5")
        
        // Test start
        let startValue = track.value(at: .zero)
        XCTAssertEqual(startValue, 0.0, accuracy: 0.01, "Value at start should be 0.0")
        
        // Test end
        let endValue = track.value(at: CMTime(seconds: 1.0, preferredTimescale: 600))
        XCTAssertEqual(endValue, 1.0, accuracy: 0.01, "Value at end should be 1.0")
    }
    
    func testKeyframeAccess() {
        var animation = KeyframeAnimation()
        let opacityTrack = KeyframeTrack(property: .opacity, keyframes: [
            Keyframe(time: CMTime(seconds: 0, preferredTimescale: 600), value: 0),
            Keyframe(time: CMTime(seconds: 1, preferredTimescale: 600), value: 1)
        ])
        
        // Test subscript access
        animation[.opacity] = opacityTrack
        
        let valueStart = animation.value(for: .opacity, at: CMTime(seconds: 0, preferredTimescale: 600))
        let valueEnd = animation.value(for: .opacity, at: CMTime(seconds: 1, preferredTimescale: 600))
        
        XCTAssertEqual(valueStart, 0)
        XCTAssertEqual(valueEnd, 1)
    }
    
    func testKeyframeInterpolation() {
        // Linear interpolation 0->1 over 1 second
        let track = KeyframeTrack(property: .rotation, keyframes: [
            Keyframe(time: CMTime(seconds: 0, preferredTimescale: 600), value: 0, easing: .linear),
            Keyframe(time: CMTime(seconds: 1, preferredTimescale: 600), value: 100)
        ])
        
        var animationWithTrack = KeyframeAnimation()
        animationWithTrack[.rotation] = track
        
        let valueMid = animationWithTrack.value(for: .rotation, at: CMTime(seconds: 0.5, preferredTimescale: 600))
        
        XCTAssertEqual(valueMid, 50, accuracy: 0.1)
    }
    
    func testKeyframeCodable() throws {
        var animation = KeyframeAnimation()
        let track = KeyframeTrack(property: .opacity, keyframes: [
            Keyframe(time: .zero, value: 0.5)
        ])
        animation[.opacity] = track
        XCTAssertFalse(animation.isEmpty, "Animation with tracks should not be empty")
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(animation)
        XCTAssertFalse(data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedAnimation = try decoder.decode(KeyframeAnimation.self, from: data)
        XCTAssertEqual(decodedAnimation[.opacity]?.keyframes.first?.value, 0.5)
    }
    
    // MARK: - Transition Tests
    
    func testTransitionTypeDisplayNames() {
        XCTAssertEqual(TransitionType.dissolve.displayName, "Dissolve")
        XCTAssertEqual(TransitionType.fadeToBlack.displayName, "Fade Black")
        XCTAssertEqual(TransitionType.none.displayName, "None")
    }
    
    func testTransitionDefaultDurations() {
        XCTAssertEqual(TransitionType.dissolve.defaultDuration, 0.5)
        XCTAssertEqual(TransitionType.none.defaultDuration, 0.0)
        XCTAssertEqual(TransitionType.pushRight.defaultDuration, 0.4)
    }
    
    func testVideoTransitionCreation() {
        let transition = VideoTransition(type: .dissolve)
        XCTAssertEqual(transition.type, .dissolve)
        XCTAssertEqual(transition.duration.seconds, 0.5, accuracy: 0.01)
        
        let customDuration = VideoTransition(type: .wipeRight, duration: CMTime(seconds: 1.5, preferredTimescale: 600))
        XCTAssertEqual(customDuration.duration.seconds, 1.5, accuracy: 0.01)
    }
    
    func testTransitionApplyNone() {
        let transition = VideoTransition(type: .none)
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let target = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        // Progress < 0.5 should show source
        let beforeMid = transition.apply(from: source, to: target, progress: 0.25)
        XCTAssertNotNil(beforeMid, "Transition should produce output")
        
        // Progress >= 0.5 should show target
        let afterMid = transition.apply(from: source, to: target, progress: 0.75)
        XCTAssertNotNil(afterMid, "Transition should produce output")
    }
    
    func testTransitionDissolve() {
        let transition = VideoTransition(type: .dissolve)
        let source = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let target = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        let result = transition.apply(from: source, to: target, progress: 0.5)
        XCTAssertNotNil(result, "Dissolve transition should produce output")
    }
    
    // MARK: - VideoEffect Tests
    
    func testVideoEffectCreation() {
        let blur = VideoEffect(type: .blur)
        XCTAssertEqual(blur.type, .blur)
        XCTAssertEqual(blur.intensity, 5.0, "Default intensity should be 5.0")
        
        let customSaturation = VideoEffect(type: .saturation, intensity: 0.8)
        XCTAssertEqual(customSaturation.intensity, 0.8)
    }
    
    func testVideoEffectFilterCreation() {
        let blur = VideoEffect(type: .blur, intensity: 1.0)
        let filter = blur.createFilter()
        XCTAssertNotNil(filter, "Blur effect should create a CIFilter")
        
        let brightness = VideoEffect(type: .brightness, intensity: 0.5)
        let brightnessFilter = brightness.createFilter()
        XCTAssertNotNil(brightnessFilter, "Brightness effect should create a CIFilter")
    }
    
    func testVideoEffectApply() {
        let blur = VideoEffect(type: .blur, intensity: 0.5)
        let inputImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        let result = blur.apply(to: inputImage)
        XCTAssertNotNil(result, "Effect should produce output image")
    }
    
    // MARK: - VideoClip Keyframe Integration Tests
    
    func testVideoClipKeyframeProperty() {
        var clip = VideoClip(url: URL(fileURLWithPath: "/test.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        XCTAssertNil(clip.keyframeAnimation, "New clip should have nil keyframeAnimation")
        
        var animation = KeyframeAnimation()
        var track = KeyframeTrack(property: .opacity)
        track.keyframes = [Keyframe(time: .zero, value: 1.0, easing: .linear)]
        animation[.opacity] = track
        
        clip.keyframeAnimation = animation
        XCTAssertNotNil(clip.keyframeAnimation, "Keyframe animation should be set")
        XCTAssertFalse(clip.keyframeAnimation!.isEmpty, "Animation should not be empty")
    }
    
    func testVideoClipTransitionProperty() {
        var clip = VideoClip(url: URL(fileURLWithPath: "/test.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        XCTAssertNil(clip.transition, "New clip should have nil transition")
        
        clip.transition = VideoTransition(type: .dissolve)
        XCTAssertNotNil(clip.transition)
        XCTAssertEqual(clip.transition?.type, .dissolve)
    }
    
    func testVideoClipEffectsProperty() {
        var clip = VideoClip(url: URL(fileURLWithPath: "/test.mov"), duration: CMTime(seconds: 10, preferredTimescale: 600))
        XCTAssertTrue(clip.effects.isEmpty, "New clip should have empty effects")
        
        clip.effects.append(VideoEffect(type: .blur))
        clip.effects.append(VideoEffect(type: .vignette))
        XCTAssertEqual(clip.effects.count, 2)
    }
    
    // MARK: - TransitionMetadata Tests
    
    func testTransitionMetadataCreation() {
        let timeRange = CMTimeRange(start: CMTime(seconds: 5.0, preferredTimescale: 600),
                                     duration: CMTime(seconds: 0.5, preferredTimescale: 600))
        let meta = TransitionMetadata(timeRange: timeRange,
                                      fromTrackID: 1,
                                      toTrackID: 2,
                                      type: .dissolve)
        
        XCTAssertEqual(meta.fromTrackID, 1)
        XCTAssertEqual(meta.toTrackID, 2)
        XCTAssertEqual(meta.type, .dissolve)
        XCTAssertEqual(meta.timeRange.duration.seconds, 0.5, accuracy: 0.01)
    }
}
