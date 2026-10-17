//
//  CancellationTests.swift
//  SaneVideoTests
//
//  Cancelling processing must stop the running task and clear progress state.
//

import Foundation
@testable import SaneVideo
import Testing

@Suite("Processing cancellation")
@MainActor
struct CancellationTests {
    @Test("cancelProcessing cancels the stored task and clears transactions and progress")
    func cancelProcessingStopsTaskAndResetsState() async {
        let projectState = ProjectState()
        let transaction = projectState.beginTransaction()
        projectState.updateTransactionProgress(transaction, progress: 0.4)
        projectState.processingStatus = "Removing silence"

        let task = Task<Void, Error> {
            // Stays suspended until cancelled; cancellation ends the sleep at once.
            try await Task.sleep(for: .seconds(60))
        }
        projectState.setProcessingTask(task)
        #expect(projectState.isProcessing)

        await projectState.cancelProcessing()

        #expect(task.isCancelled)
        #expect(!projectState.isProcessing)
        #expect(projectState.processingStatus == nil)
        #expect(projectState.processingProgress == 0.0)
        #expect(projectState.activeTransactionCount == 0)

        // The task must actually end with CancellationError, not keep running.
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
    }
}
