import AppKit
import CoreMedia
import Foundation
import Testing

@testable import SaneVideo

@Suite("Video Clip Tests")
struct VideoClipTests {

  // MARK: - VideoClip Removed Ranges Logic

  @Test("Removed ranges integration and effective duration")
  func removedRangesIntegration() {
    let url = URL(fileURLWithPath: "/tmp/test.mp4")
    var clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))

    // Remove 2-4s
    let range1 = CMTimeRange(
      start: CMTime(seconds: 2, preferredTimescale: 600),
      duration: CMTime(seconds: 2, preferredTimescale: 600))
    clip.addRemovedRange(range1)

    #expect(clip.removedRanges.count == 1)
    #expect(clip.effectiveDuration.seconds == 8.0)

    // Remove 6-7s
    let range2 = CMTimeRange(
      start: CMTime(seconds: 6, preferredTimescale: 600),
      duration: CMTime(seconds: 1, preferredTimescale: 600))
    clip.addRemovedRange(range2)

    #expect(clip.removedRanges.count == 2)
    #expect(clip.effectiveDuration.seconds == 7.0)
  }

  // MARK: - Filler Logic Verification

  @Test("Filler word detection and range extraction")
  func fillerWordDetectionLogic() {
    let start = CMTime(seconds: 0, preferredTimescale: 600)
    let end = CMTime(seconds: 5, preferredTimescale: 600)

    let words = [
      CaptionWord(text: "Hello", start: 0.0, end: 1.0, probability: 0.9),
      CaptionWord(text: "Um", start: 1.0, end: 2.0, probability: 0.8),
      CaptionWord(text: "World", start: 2.0, end: 3.0, probability: 0.9)
    ]

    let caption = Caption(text: "Hello Um World", startTime: start, endTime: end, words: words)
    let fillerWords: Set<String> = ["um", "uh"]
    var detectedRanges: [CMTimeRange] = []

    if let words = caption.words, !words.isEmpty {
      for word in words {
        let cleanedWord = word.text
          .lowercased()
          .trimmingCharacters(in: .punctuationCharacters)

        if fillerWords.contains(cleanedWord) {
          detectedRanges.append(word.timeRange)
        }
      }
    }

    #expect(detectedRanges.count == 1)
    #expect(detectedRanges.first?.start.seconds == 1.0)
    #expect(detectedRanges.first?.duration.seconds == 1.0)
  }

  // MARK: - Serialization Tests

  @Test("Caption and word serialization")
  func captionWordSerialization() throws {
    let word = CaptionWord(text: "Testing", start: 1.5, end: 2.5, probability: 0.99)
    let caption = Caption(
      text: "Testing", startTime: .zero, endTime: CMTime(seconds: 5, preferredTimescale: 600),
      words: [word])

    let encoder = JSONEncoder()
    let data = try encoder.encode(caption)

    let decoder = JSONDecoder()
    let decodedCaption = try decoder.decode(Caption.self, from: data)

    #expect(decodedCaption.words?.count == 1)
    #expect(decodedCaption.words?.first?.text == "Testing")
    #expect(decodedCaption.words?.first?.start == 1.5)
  }

  @Test("VideoEffect persistence")
  func effectsPersistence() throws {
    let url = URL(fileURLWithPath: "/tmp/test.mp4")
    var clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))

    let effect = VideoEffect(type: .autoEnhance)
    clip.effects = [effect]

    // Encode
    let encoder = JSONEncoder()
    let data = try encoder.encode(clip)

    // Decode
    let decoder = JSONDecoder()
    let decodedClip = try decoder.decode(VideoClip.self, from: data)

    // Verify
    #expect(decodedClip.effects.count == 1)
    #expect(decodedClip.effects.first?.type == .autoEnhance)
  }

  @Test("Advanced properties persistence")
  func advancedPersistence() throws {
    let url = URL(fileURLWithPath: "/tmp/test.mp4")
    var clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))

    // Set advanced properties
    clip.opacity = 0.5
    clip.enhancedAudioURL = URL(fileURLWithPath: "/tmp/enhanced.wav")

    // Encode
    let encoder = JSONEncoder()
    let data = try encoder.encode(clip)

    // Decode
    let decoder = JSONDecoder()
    let decodedClip = try decoder.decode(VideoClip.self, from: data)

    // Verify
    #expect(decodedClip.opacity == 0.5)
    #expect(decodedClip.enhancedAudioURL?.path == "/tmp/enhanced.wav")
  }

  @Test("Demo studio sidecars and overlay style persist")
  func demoStudioPersistence() throws {
    let url = URL(fileURLWithPath: "/tmp/test.mp4")
    var clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))

    clip.clickDataURL = URL(fileURLWithPath: "/tmp/test.clicks.json")
    clip.cursorDataURL = URL(fileURLWithPath: "/tmp/test.cursor.json")
    clip.keystrokeDataURL = URL(fileURLWithPath: "/tmp/test.keys.json")
    clip.interactionOverlayStyle = InteractionOverlayStyle(
      highlightClicks: true,
      spotlightCursor: false,
      showKeystrokes: true,
      clickRingScale: 1.4,
      spotlightOpacity: 0.5
    )

    let data = try JSONEncoder().encode(clip)
    let decodedClip = try JSONDecoder().decode(VideoClip.self, from: data)

    #expect(decodedClip.clickDataURL == clip.clickDataURL)
    #expect(decodedClip.cursorDataURL == clip.cursorDataURL)
    #expect(decodedClip.keystrokeDataURL == clip.keystrokeDataURL)
    #expect(decodedClip.interactionOverlayStyle == clip.interactionOverlayStyle)
  }

  @Test("Keystroke sample display text preserves modifier order")
  func keystrokeDisplayText() {
    let sample = KeystrokeSample(
      timestamp: 1.5,
      key: "K",
      modifiers: ["Command", "Shift"],
      keyCode: 40
    )

    #expect(sample.displayText == "Command + Shift + K")
  }

  @Test("Interaction sidecars only report ready when they contain samples")
  func interactionSidecarReadiness() throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let clickURL = base.appendingPathExtension("clicks.json")
    let cursorURL = base.appendingPathExtension("cursor.json")
    let keyURL = base.appendingPathExtension("keys.json")
    defer {
      try? FileManager.default.removeItem(at: clickURL)
      try? FileManager.default.removeItem(at: cursorURL)
      try? FileManager.default.removeItem(at: keyURL)
    }

    var clip = VideoClip(
      url: URL(fileURLWithPath: "/tmp/test.mp4"),
      duration: CMTime(seconds: 10, preferredTimescale: 600)
    )
    clip.clickDataURL = clickURL
    clip.cursorDataURL = cursorURL
    clip.keystrokeDataURL = keyURL

    try JSONEncoder().encode([ClickSample]()).write(to: clickURL)
    try JSONEncoder().encode([CursorSample]()).write(to: cursorURL)
    try JSONEncoder().encode([KeystrokeSample]()).write(to: keyURL)

    #expect(clip.hasRecordedClickData == false)
    #expect(clip.hasRecordedCursorData == false)
    #expect(clip.hasRecordedKeystrokeData == false)

    try JSONEncoder().encode([
      ClickSample(timestamp: 1.0, x: 0.4, y: 0.6, button: 0)
    ]).write(to: clickURL)
    try JSONEncoder().encode([
      CursorSample(timestamp: 1.0, x: 0.4, y: 0.6, isDown: false, button: 0)
    ]).write(to: cursorURL)
    try JSONEncoder().encode([
      KeystrokeSample(timestamp: 1.0, key: "K", modifiers: ["Command"], keyCode: 40)
    ]).write(to: keyURL)

    #expect(clip.hasRecordedClickData)
    #expect(clip.hasRecordedCursorData)
    #expect(clip.hasRecordedKeystrokeData)
  }

  @Test("Voiceover save panel prefers key window, then main window")
  @MainActor
  func voiceoverPreferredWindowPriority() {
    let keyWindow = TestWindow(visible: true)
    let mainWindow = TestWindow(visible: true)
    let fallbackWindow = TestWindow(visible: true)

    let preferredWithKey = VoiceoverSettingsSheet.preferredPresentationWindow(
      keyWindow: keyWindow,
      mainWindow: mainWindow,
      windows: [fallbackWindow]
    )
    #expect(preferredWithKey === keyWindow)

    let preferredWithMain = VoiceoverSettingsSheet.preferredPresentationWindow(
      keyWindow: nil,
      mainWindow: mainWindow,
      windows: [fallbackWindow]
    )
    #expect(preferredWithMain === mainWindow)
  }

  @Test("Voiceover save panel falls back to the first visible window")
  @MainActor
  func voiceoverPreferredWindowVisibleFallback() {
    let hiddenWindow = TestWindow(visible: false)
    let visibleWindow = TestWindow(visible: true)

    let preferred = VoiceoverSettingsSheet.preferredPresentationWindow(
      keyWindow: nil,
      mainWindow: nil,
      windows: [hiddenWindow, visibleWindow]
    )

    #expect(preferred === visibleWindow)
  }
}

@MainActor
private final class TestWindow: NSWindow {
  private let forcedVisible: Bool

  init(visible: Bool) {
    self.forcedVisible = visible
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
  }

  override var isVisible: Bool {
    forcedVisible
  }
}
