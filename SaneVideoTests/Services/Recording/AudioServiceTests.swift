//
//  AudioServiceTests.swift
//  SaneVideoTests
//
//  The real AudioService must hand every subscriber the same publishers, or the
//  recorder and the level meter end up listening to different subjects.
//

import Combine
@testable import SaneVideo
import Testing

@Suite("Audio Service")
@MainActor
struct AudioServiceTests {
    @Test("Publishers are the same object on every access and deliver sent levels")
    func publishersRemainStableAcrossAccesses() {
        let service = AudioService(permissionManager: PermissionManager())

        #expect(service.sampleBufferSubject === service.sampleBufferSubject)
        #expect(service.audioLevelSubject === service.audioLevelSubject)

        var receivedLevels: [Float] = []
        let cancellable = service.audioLevelSubject.sink { receivedLevels.append($0) }
        defer { cancellable.cancel() }

        service.audioLevelSubject.send(0.42)

        #expect(receivedLevels == [0.42])
    }
}
