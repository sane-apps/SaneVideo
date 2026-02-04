//
//  RenderQueueTests.swift
//  SaneVideoTests
//
//  Tests for RenderQueue actor ensuring FIFO ordering.
//

@testable import SaneVideo
import Testing

struct RenderQueueTests {
    @Test("Requests complete in FIFO order")
    func fifoOrder() async {
        let queue = RenderQueue()
        var completionOrder: [Int] = []

        // Enqueue work with varying durations
        for i in 0 ..< 5 {
            await queue.enqueue {
                // Simulate varying work durations
                try? await Task.sleep(for: .milliseconds(Int.random(in: 1 ... 10)))
                completionOrder.append(i)
            }
        }

        // Wait for all to complete
        try? await Task.sleep(for: .milliseconds(100))
        #expect(completionOrder == [0, 1, 2, 3, 4])
    }

    @Test("Single request completes correctly")
    func singleRequest() async {
        let queue = RenderQueue()
        var completed = false

        await queue.enqueue {
            completed = true
        }

        // Give it a moment to process
        try? await Task.sleep(for: .milliseconds(10))
        #expect(completed)
    }

    @Test("Empty queue handles enqueue correctly")
    func emptyQueue() async {
        let queue = RenderQueue()
        var executionCount = 0

        await queue.enqueue {
            executionCount += 1
        }

        await queue.enqueue {
            executionCount += 1
        }

        // Wait for processing
        try? await Task.sleep(for: .milliseconds(20))
        #expect(executionCount == 2)
    }
}
