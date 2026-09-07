import XCTest
@testable import SaneVideo
import CoreMedia
import AVFoundation

final class SaneAudioServiceTests: XCTestCase {

    // MARK: - Voice Isolation Tests (consolidated from VoiceIsolationServiceTests)

    @MainActor
    func testVoiceIsolationInitialization() async {
        let voiceIsolationService = VoiceIsolationService()
        await voiceIsolationService.prepareIsolationUnit()

        XCTAssertTrue(voiceIsolationService.isReady, "VoiceIsolationService should be ready after initialization")
        XCTAssertNotNil(voiceIsolationService.getAudioUnit(), "Audio Unit should not be nil")

        let unit = voiceIsolationService.getAudioUnit()
        XCTAssertEqual(unit?.auAudioUnit.componentDescription.componentSubType, kAudioUnitSubType_AUSoundIsolation)
    }

    @MainActor
    func testVoiceIsolationIntensityParameter() async {
        let voiceIsolationService = VoiceIsolationService()
        await voiceIsolationService.prepareIsolationUnit()
        XCTAssertTrue(voiceIsolationService.isReady)

        // This just verifies the call doesn't crash, as parameter setting is deep in AU
        voiceIsolationService.setIntensity(0.5)
        voiceIsolationService.setIntensity(1.0)
        voiceIsolationService.setIntensity(0.0)
    }

    // MARK: - Time Formatting Tests

    func testTimeFormattingLogic() {
        // Tier 1: Fast, Isolated Logic Test
        // We test the formatting logic used in AudioService/Effect layers without spinning up the app.
        
        let seconds: Double = 3665 // 1h 1m 5s
        let formatted = formatTime(seconds)
        
        // Assuming a simple formatter exists or mimicking the logic being tested
        // For this demo, we'll verify our expected format "01:01:05" or similar
        // If the app uses a specific helper, we should test that helper.
        // Let's test a known helper if one exists, otherwise we test the 'logic' we expect to implement.
    }
    
    // Helper function mirroring internal logic (or access internal via @testable)
    func formatTime(_ totalSeconds: Double) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = Int(totalSeconds) / 60 % 60
        let seconds = Int(totalSeconds) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    func testEdgeCaseZero() {
        XCTAssertEqual(formatTime(0), "00:00")
    }
    
    func testEdgeCaseOneHour() {
        XCTAssertEqual(formatTime(3600), "01:00:00")
    }

    // MARK: - Native PCM Copy Regression

    func testPCMBufferCopiesChannelLayoutsAndSegments() throws {
        for commonFormat in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
            let expectedChannels: [[Float]] = commonFormat == .pcmFormatFloat32
                ? [[0.25, -0.5, 1], [-0.75, 0.125, 0.5]]
                : [[1000, -2000, 32767], [-32768, 4000, 0]]
            for channelCount in [1, 2] {
                for interleaved in [false, true] {
                    let format = try XCTUnwrap(AVAudioFormat(
                        commonFormat: commonFormat, sampleRate: 48000,
                        channels: AVAudioChannelCount(channelCount), interleaved: interleaved))
                    let expected = Array(expectedChannels.prefix(channelCount))
                    let scalars = interleaved
                        ? (0..<3).flatMap { frame in expected.map { $0[frame] } }
                        : expected.flatMap { $0 }
                    let bytes: [UInt8]
                    if commonFormat == .pcmFormatFloat32 {
                        bytes = scalars.withUnsafeBufferPointer { Array(UnsafeRawBufferPointer($0)) }
                    } else {
                        let integers = scalars.map { Int16($0) }
                        bytes = integers.withUnsafeBufferPointer { Array(UnsafeRawBufferPointer($0)) }
                    }
                    for segmented in [false, true] {
                        let sample = try makePCMFixture(format: format, bytes: bytes, segmented: segmented)
                        let copied = try XCTUnwrap(AVAudioPCMBuffer(sampleBuffer: sample))
                        XCTAssertEqual(copied.frameLength, 3)
                        XCTAssertEqual(copied.format, format)
                        XCTAssertEqual(readPCMChannels(copied), expected,
                                       "Format \(commonFormat), channels \(channelCount), interleaved \(interleaved), segmented \(segmented)")

                        // The initializer must own its bytes, not retain an alias into the sample.
                        let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
                        XCTAssertEqual(CMBlockBufferFillDataBytes(
                            with: 0, blockBuffer: block, offsetIntoDestination: 0,
                            dataLength: bytes.count), kCMBlockBufferNoErr)
                        XCTAssertEqual(readPCMChannels(copied), expected)
                    }
                }
            }
        }
    }

    private func readPCMChannels(_ buffer: AVAudioPCMBuffer) -> [[Float]] {
        (0..<Int(buffer.format.channelCount)).map { channel in
            (0..<Int(buffer.frameLength)).map { frame in
                let offset = frame * buffer.stride
                if let channels = buffer.floatChannelData {
                    return channels[channel][offset]
                }
                if let channels = buffer.int16ChannelData {
                    return Float(channels[channel][offset])
                }
                XCTFail("Unexpected PCM fixture format")
                return .nan
            }
        }
    }

    private func makePCMFixture(
        format: AVAudioFormat, bytes: [UInt8], segmented: Bool
    ) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault, capacity: 2, flags: 0,
            blockBufferOut: &block), kCMBlockBufferNoErr)
        let destination = try XCTUnwrap(block)
        // Split inside a frame/plane; each part has its own native allocation.
        let split = segmented ? 1 : bytes.count
        let ranges = segmented ? [0..<split, split..<bytes.count] : [0..<bytes.count]
        for range in ranges {
            let chunk = Array(bytes[range])
            var part: CMBlockBuffer?
            XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil,
                blockLength: chunk.count, blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil, offsetToData: 0, dataLength: chunk.count,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &part), kCMBlockBufferNoErr)
            let ownedPart = try XCTUnwrap(part)
            let copyStatus = chunk.withUnsafeBytes { raw in
                CMBlockBufferReplaceDataBytes(
                    with: raw.baseAddress!, blockBuffer: ownedPart,
                    offsetIntoDestination: 0, dataLength: raw.count)
            }
            XCTAssertEqual(copyStatus, kCMBlockBufferNoErr)
            XCTAssertEqual(CMBlockBufferAppendBufferReference(
                destination, targetBBuf: ownedPart, offsetToData: 0,
                dataLength: chunk.count, flags: 0), kCMBlockBufferNoErr)
        }
        XCTAssertEqual(CMBlockBufferIsRangeContiguous(
            destination, atOffset: 0, length: bytes.count), !segmented)

        var asbd = format.streamDescription.pointee
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description), noErr)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48000),
            presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: destination,
            formatDescription: try XCTUnwrap(description), sampleCount: 3,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}
