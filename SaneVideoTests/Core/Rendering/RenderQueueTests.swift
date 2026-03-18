//
//  RenderQueueTests.swift
//  SaneVideoTests
//
//  Tests for RenderQueue actor ensuring FIFO ordering.
//

@testable import SaneVideo
import Testing

struct RenderQueueTests {
    private actor CompletionRecorder {
        private var values: [Int] = []

        func append(_ value: Int) {
            values.append(value)
        }

        func snapshot() -> [Int] {
            values
        }
    }

    private actor BoolRecorder {
        private var value = false

        func setTrue() {
            value = true
        }

        func snapshot() -> Bool {
            value
        }
    }

    private actor CounterRecorder {
        private var value = 0

        func increment() {
            value += 1
        }

        func snapshot() -> Int {
            value
        }
    }

    @Test("Requests complete in FIFO order")
    func fifoOrder() async {
        let queue = RenderQueue()
        let completionOrder = CompletionRecorder()

        // Enqueue work with varying durations
        for i in 0 ..< 5 {
            await queue.enqueue {
                // Simulate varying work durations
                try? await Task.sleep(for: .milliseconds(Int.random(in: 1 ... 10)))
                await completionOrder.append(i)
            }
        }

        // Wait for all to complete
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await completionOrder.snapshot() == [0, 1, 2, 3, 4])
    }

    @Test("Single request completes correctly")
    func singleRequest() async {
        let queue = RenderQueue()
        let completed = BoolRecorder()

        await queue.enqueue {
            await completed.setTrue()
        }

        // Give it a moment to process
        try? await Task.sleep(for: .milliseconds(10))
        #expect(await completed.snapshot())
    }

    @Test("Empty queue handles enqueue correctly")
    func emptyQueue() async {
        let queue = RenderQueue()
        let executionCount = CounterRecorder()

        await queue.enqueue {
            await executionCount.increment()
        }

        await queue.enqueue {
            await executionCount.increment()
        }

        // Wait for processing
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await executionCount.snapshot() == 2)
    }
}
