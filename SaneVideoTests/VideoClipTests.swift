import Testing
import CoreMedia
import Foundation
@testable import SaneVideo

@Suite("Video Clip Tests")
struct VideoClipTests {

    // MARK: - VideoClip Removed Ranges Logic
    
    @Test("Removed ranges integration and effective duration")
    func removedRangesIntegration() {
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        var clip = VideoClip(url: url, duration: CMTime(seconds: 10, preferredTimescale: 600))
        
        // Remove 2-4s
        let range1 = CMTimeRange(start: CMTime(seconds: 2, preferredTimescale: 600), duration: CMTime(seconds: 2, preferredTimescale: 600))
        clip.addRemovedRange(range1)
        
        #expect(clip.removedRanges.count == 1)
        #expect(clip.effectiveDuration.seconds == 8.0)
        
        // Remove 6-7s
        let range2 = CMTimeRange(start: CMTime(seconds: 6, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))
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
        let caption = Caption(text: "Testing", startTime: .zero, endTime: CMTime(seconds: 5, preferredTimescale: 600), words: [word])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(caption)
        
        let decoder = JSONDecoder()
        let decodedCaption = try decoder.decode(Caption.self, from: data)
        
        #expect(decodedCaption.words?.count == 1)
        #expect(decodedCaption.words?.first?.text == "Testing")
        #expect(decodedCaption.words?.first?.start == 1.5)
    }
}
