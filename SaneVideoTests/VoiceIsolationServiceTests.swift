//
//  VoiceIsolationServiceTests.swift
//  SaneVideoTests
//

import XCTest
import AVFoundation
@testable import SaneVideo

@MainActor
final class VoiceIsolationServiceTests: XCTestCase {
    
    var service: VoiceIsolationService!
    
    override func setUp() {
        super.setUp()
        service = VoiceIsolationService()
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    func testInitialization() async {
        // Wait for initialization task to complete
        await service.prepareIsolationUnit()
        
        XCTAssertTrue(service.isReady, "VoiceIsolationService should be ready after initialization")
        XCTAssertNotNil(service.getAudioUnit(), "Audio Unit should not be nil")
        
        let unit = service.getAudioUnit()
        XCTAssertEqual(unit?.auAudioUnit.componentDescription.componentSubType, kAudioUnitSubType_AUSoundIsolation)
    }
    
    func testIntensityParameter() async {
        await service.prepareIsolationUnit()
        XCTAssertTrue(service.isReady)
        
        // This just verifies the call doesn't crash, as parameter setting is deep in AU
        service.setIntensity(0.5)
        service.setIntensity(1.0)
        service.setIntensity(0.0)
    }
}
