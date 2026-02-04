//
//  RenderQueue.swift
//  SaneVideo
//
//  Ensures video composition requests complete in the order they were submitted.
//  Prevents frame reordering caused by unstructured concurrency.
//

import AVFoundation

/// Ensures video composition requests complete in the order they were submitted.
/// Prevents frame reordering caused by unstructured concurrency.
actor RenderQueue {
    private var pendingRequests: [(id: Int, work: @Sendable () async -> Void)] = []
    private var nextSequenceID: Int = 0
    private var isProcessing = false

    /// Enqueue a render operation. Operations execute serially in submission order.
    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let id = nextSequenceID
        nextSequenceID += 1
        pendingRequests.append((id: id, work: work))

        if !isProcessing {
            isProcessing = true
            Task { await processQueue() }
        }
    }

    private func processQueue() async {
        while !pendingRequests.isEmpty {
            let next = pendingRequests.removeFirst()
            await next.work()
        }
        isProcessing = false
    }
}
