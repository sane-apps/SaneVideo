import CoreImage
import CoreMedia
import Foundation
@testable import SaneVideo
import Testing

/// Rendering pipeline: keyframes, transitions, effects and interaction overlays.
@Suite("Rendering Pipeline")
struct RenderingPipelineTests {
    private static let square = CGRect(x: 0, y: 0, width: 16, height: 16)

    /// Renders the centre pixel of `image` as 0...1 RGBA, with no color management.
    private func centerPixel(of image: CIImage) -> (r: Double, g: Double, b: Double) {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var bytes = [UInt8](repeating: 0, count: 4)
        let center = CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1)
        context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: center, format: .RGBA8, colorSpace: nil)
        return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255)
    }

    private func solid(_ color: CIColor) -> CIImage {
        CIImage(color: color).cropped(to: Self.square)
    }

    // MARK: - Keyframes

    @Test("Linear keyframe track interpolates start, middle and end")
    func keyframeInterpolationLinear() {
        var track = KeyframeTrack(property: .opacity)
        track.keyframes = [
            Keyframe(time: .zero, value: 0.0, easing: .linear),
            Keyframe(time: CMTime(seconds: 1.0, preferredTimescale: 600), value: 1.0, easing: .linear)
        ]

        #expect(abs(track.value(at: .zero) - 0.0) < 0.01)
        #expect(abs(track.value(at: CMTime(seconds: 0.5, preferredTimescale: 600)) - 0.5) < 0.01)
        #expect(abs(track.value(at: CMTime(seconds: 1.0, preferredTimescale: 600)) - 1.0) < 0.01)
    }

    @Test("Animation subscript stores a track that value(for:at:) reads back interpolated")
    func keyframeAnimationSubscript() {
        var animation = KeyframeAnimation()
        animation[.rotation] = KeyframeTrack(property: .rotation, keyframes: [
            Keyframe(time: .zero, value: 0, easing: .linear),
            Keyframe(time: CMTime(seconds: 1, preferredTimescale: 600), value: 100)
        ])

        let mid = animation.value(for: .rotation, at: CMTime(seconds: 0.5, preferredTimescale: 600))
        #expect(abs(mid - 50) < 0.1)
    }

    @Test("Keyframe animation survives an encode/decode round trip")
    func keyframeCodable() throws {
        var animation = KeyframeAnimation()
        animation[.opacity] = KeyframeTrack(property: .opacity, keyframes: [Keyframe(time: .zero, value: 0.5)])

        let data = try JSONEncoder().encode(animation)
        let decoded = try JSONDecoder().decode(KeyframeAnimation.self, from: data)
        #expect(decoded[.opacity]?.keyframes.first?.value == 0.5)
    }

    // MARK: - Transitions

    @Test("Cut transition shows the source before halfway and the target after")
    func cutTransitionSwitchesAtHalfway() throws {
        let transition = VideoTransition(type: .none)
        let red = solid(.red)
        let blue = solid(.blue)

        let before = try #require(transition.apply(from: red, to: blue, progress: 0.25))
        let after = try #require(transition.apply(from: red, to: blue, progress: 0.75))

        #expect(centerPixel(of: before).r > 0.9)
        #expect(centerPixel(of: after).b > 0.9)
    }

    @Test("Dissolve at halfway blends source and target")
    func dissolveBlendsAtHalfway() throws {
        let transition = VideoTransition(type: .dissolve)
        let result = try #require(transition.apply(from: solid(.red), to: solid(.blue), progress: 0.5))
        let pixel = centerPixel(of: result)

        #expect(pixel.r > 0.3 && pixel.r < 0.7)
        #expect(pixel.b > 0.3 && pixel.b < 0.7)
    }

    // MARK: - Effects

    @Test("Brightness effect brightens the image")
    func brightnessEffectBrightens() throws {
        let gray = solid(CIColor(red: 0.4, green: 0.4, blue: 0.4))
        let effect = VideoEffect(type: .brightness, intensity: 0.3)
        let output = try #require(effect.apply(to: gray))

        #expect(centerPixel(of: output).r > centerPixel(of: gray).r + 0.1)
    }

    // MARK: - Interaction overlays

    @Test("Interaction renderer draws an overlay when click, cursor and key data are present")
    func interactionOverlayRendererProducesImage() {
        let layer = InteractionLayerItem(
            clipID: UUID(),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)),
            clicks: [InteractionClickItem(time: CMTime(seconds: 0.5, preferredTimescale: 600), x: 0.5, y: 0.5, button: 0)],
            cursorPath: [
                InteractionCursorItem(time: .zero, x: 0.4, y: 0.4, isDown: false),
                InteractionCursorItem(time: CMTime(seconds: 1.0, preferredTimescale: 600), x: 0.6, y: 0.5, isDown: false)
            ],
            keystrokes: [
                InteractionKeystrokeItem(id: UUID(), time: CMTime(seconds: 0.75, preferredTimescale: 600), text: "Command + K")
            ],
            style: InteractionOverlayStyle()
        )

        let image = InteractionOverlayRenderer.renderInteractionLayers(
            [layer],
            size: CGSize(width: 1920, height: 1080),
            compositionTime: CMTime(seconds: 0.9, preferredTimescale: 600)
        )

        #expect(image != nil)
    }

    @Test("Interaction overlay builder maps sidecar timestamps onto composition time")
    func interactionOverlayBuilderMapsSidecarsToCompositionTime() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let videoURL = tempDirectory.appendingPathComponent("demo.mp4")
        let clickURL = tempDirectory.appendingPathComponent("demo.clicks.json")
        let cursorURL = tempDirectory.appendingPathComponent("demo.cursor.json")
        let keysURL = tempDirectory.appendingPathComponent("demo.keys.json")

        FileManager.default.createFile(atPath: videoURL.path, contents: Data(), attributes: nil)
        try JSONEncoder().encode([ClickSample(timestamp: 1.0, x: 0.25, y: 0.4, button: 0)]).write(to: clickURL)
        try JSONEncoder().encode([CursorSample(timestamp: 1.0, x: 0.3, y: 0.5)]).write(to: cursorURL)
        try JSONEncoder().encode([KeystrokeSample(timestamp: 1.0, key: "K", modifiers: ["Command"], keyCode: 40)])
            .write(to: keysURL)

        var clip = VideoClip(url: videoURL, duration: CMTime(seconds: 10, preferredTimescale: 600))
        clip.clickDataURL = clickURL
        clip.cursorDataURL = cursorURL
        clip.keystrokeDataURL = keysURL
        clip.startTime = CMTime(seconds: 5, preferredTimescale: 600)

        let track = Track(name: "Video", type: .video, clips: [clip], zIndex: 0)
        let interactionLayers = TextLayerBuilder.buildInteractionLayers(from: [track])

        #expect(interactionLayers.count == 1)
        #expect(abs((interactionLayers.first?.clicks.first?.time.seconds ?? -1) - 6.0) < 0.001)
        #expect(abs((interactionLayers.first?.cursorPath.first?.time.seconds ?? -1) - 6.0) < 0.001)
        #expect(interactionLayers.first?.keystrokes.first?.text == "Command + K")
    }
}
