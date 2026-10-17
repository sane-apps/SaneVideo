//
//  DiskSpaceMonitorTests.swift
//  SaneVideoTests
//

@testable import SaneVideo
import Testing

@Suite("Disk Space Monitor Tests")
struct DiskSpaceMonitorTests {
    @Test("Pre-flight disk check passes on the test machine from a background task")
    @MainActor
    func verifyDiskSpaceRunsOffMainActor() async {
        let monitor = DiskSpaceMonitor()

        let passed = await Task.detached {
            (try? monitor.verifyDiskSpace()) != nil
        }.value

        #expect(passed)
    }
}
