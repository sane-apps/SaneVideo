//
//  CameraManagerTests.swift
//  SaneVideoTests
//
//  Under test/automation, the real CameraManager must not touch camera hardware.
//

@testable import SaneVideo
import Testing

@Suite("Camera Manager Tests")
@MainActor
struct CameraManagerTests {
    @Test("Permissionless automation hides hardware camera discovery")
    func permissionlessAutomationSuppressesCameraDiscovery() {
        let manager = CameraManager()
        #expect(manager.availableCameras.isEmpty)
    }
}
