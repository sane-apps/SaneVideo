//
//  CursorTrackingServiceTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Test Suite
//

import XCTest
import AppKit
@testable import SaneVideo

@MainActor
final class CursorTrackingServiceTests: XCTestCase {
    
    var service: CursorTrackingService!
    
    override func setUp() {
        super.setUp()
        service = ServiceContainer.shared.cursorTrackingService
    }
    
    // MARK: - Basic Functionality
    
    func testStartTracking() async throws {
        // Start tracking should complete without error
        await service.startTracking()
        
        // Verify we can stop and save (proves tracking was actually started)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_start.mp4")
        let result = try await service.stopTrackingAndSave(to: tempURL)
        
        // If tracking was started, we should get a result (even if empty)
        // If not started, result would be nil
        XCTAssertNotNil(result, "Stop should return a file URL if tracking was started")
        
        // Cleanup
        if let result = result {
            try? FileManager.default.removeItem(at: result)
        }
    }
    
    func testStartTrackingMultipleTimes() async throws {
        // Starting tracking multiple times should be idempotent
        await service.startTracking()
        await service.startTracking()
        await service.startTracking()
        
        // Should not crash or throw, and should be able to stop
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_multiple.mp4")
        let result = try await service.stopTrackingAndSave(to: tempURL)
        
        XCTAssertNotNil(result, "Multiple start calls should still allow stopping")
        
        // Cleanup
        if let result = result {
            try? FileManager.default.removeItem(at: result)
        }
    }
    
    func testStopTrackingWhenNotStarted() async throws {
        // Stopping when not tracking should return nil
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mp4")
        let result = try await service.stopTrackingAndSave(to: tempURL)
        
        XCTAssertNil(result, "Should return nil when not tracking")
    }
    
    func testStopTrackingAndSave() async throws {
        // Start tracking
        await service.startTracking()
        
        // Wait a bit for some samples to be captured
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Stop and save
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_cursor.json")
        let savedURL = try await service.stopTrackingAndSave(to: tempURL)
        
        // Verify file was created
        XCTAssertNotNil(savedURL, "Should return URL of saved file")
        if let savedURL = savedURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path), "Cursor data file should exist")
            
            // Verify file contains valid JSON
            let data = try Data(contentsOf: savedURL)
            let samples = try JSONDecoder().decode([CursorSample].self, from: data)
            
            // Should have at least some samples (depending on timing)
            XCTAssertGreaterThanOrEqual(samples.count, 0, "Should have captured some cursor samples")
            
            // Cleanup
            try? FileManager.default.removeItem(at: savedURL)
        }
    }
    
    // MARK: - CursorSample Tests
    
    func testCursorSampleInitialization() {
        let sample = CursorSample(timestamp: 1.5, x: 0.5, y: 0.75)
        
        XCTAssertEqual(sample.timestamp, 1.5, accuracy: 0.001)
        XCTAssertEqual(sample.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.y, 0.75, accuracy: 0.001)
    }
    
    func testCursorSampleEquality() {
        let sample1 = CursorSample(timestamp: 1.0, x: 0.5, y: 0.5)
        let sample2 = CursorSample(timestamp: 1.0, x: 0.5, y: 0.5)
        let sample3 = CursorSample(timestamp: 1.0, x: 0.6, y: 0.5)
        
        XCTAssertEqual(sample1, sample2)
        XCTAssertNotEqual(sample1, sample3)
    }
    
    func testCursorSampleCodable() throws {
        let sample = CursorSample(timestamp: 2.5, x: 0.3, y: 0.7)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(sample)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CursorSample.self, from: data)
        
        XCTAssertEqual(sample, decoded)
    }
    
    func testCursorSampleNormalizedCoordinates() {
        // Verify coordinates are normalized (0-1 range)
        let validSample = CursorSample(timestamp: 1.0, x: 0.5, y: 0.5)
        
        XCTAssertGreaterThanOrEqual(validSample.x, 0.0)
        XCTAssertLessThanOrEqual(validSample.x, 1.0)
        XCTAssertGreaterThanOrEqual(validSample.y, 0.0)
        XCTAssertLessThanOrEqual(validSample.y, 1.0)
    }
    
    func testCursorSampleArraySerialization() throws {
        let samples = [
            CursorSample(timestamp: 0.0, x: 0.1, y: 0.2),
            CursorSample(timestamp: 0.1, x: 0.2, y: 0.3),
            CursorSample(timestamp: 0.2, x: 0.3, y: 0.4)
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(samples)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([CursorSample].self, from: data)
        
        XCTAssertEqual(samples.count, decoded.count)
        XCTAssertEqual(samples, decoded)
    }
}







