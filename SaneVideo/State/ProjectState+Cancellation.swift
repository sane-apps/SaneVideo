//
//  ProjectState+Cancellation.swift
//  SaneVideo
//
//  Cancellation support for long-running operations
//

import Foundation

extension ProjectState {
    /// Cancel any ongoing processing operation
    func cancelProcessing() async {
        // Cancel the task if it exists
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        
        await MainActor.run {
            isProcessing = false
            processingStatus = nil
            processingProgress = 0.0
        }
        
        AppLogger.project.info("✨ Magic Fix: Cancelled by user")
        ServiceContainer.shared.toastManager.show("Magic Fix cancelled", type: .info)
    }
    
    /// Store the processing task for cancellation
    func setProcessingTask(_ task: Task<Void, Never>) {
        currentProcessingTask = task
    }
}

