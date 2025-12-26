//
//  ScreenPreviewView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

struct ScreenPreviewView: NSViewRepresentable {
    let previewLayer: AVSampleBufferDisplayLayer

    func makeNSView(context _: Context) -> ScreenPreviewNSView {
        let view = ScreenPreviewNSView()
        view.layer = CALayer()
        view.wantsLayer = true

        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspect

        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: ScreenPreviewNSView, context _: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = nsView.bounds
        }
    }

    // CRITICAL FIX: Use static dismantleNSView to properly remove sublayers
    // This prevents use-after-free when the layer is deallocated while still
    // attached to the view hierarchy, which causes SIGSEGV/freezes during
    // autorelease pool cleanup.
    static func dismantleNSView(_ nsView: ScreenPreviewNSView, coordinator: ()) {
        // CRITICAL: Flush the sample buffer layer before removing
        // This ensures no pending samples are being processed
        if let sampleLayer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            sampleLayer.flushAndRemoveImage()
        }
        // Remove all sublayers to break the reference
        nsView.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        // CRITICAL FIX: Break all layer references
        nsView.layer?.sublayers = nil
        nsView.layer = nil
        nsView.wantsLayer = false
    }
}

// CRITICAL FIX: Custom NSView subclass that cleans up sublayers on dealloc
// This is a safety net in case dismantleNSView is not called
class ScreenPreviewNSView: NSView {
    deinit {
        // CRITICAL: Flush sample buffer layer before removing
        if let sampleLayer = layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            sampleLayer.flushAndRemoveImage()
        }
        // Remove all sublayers to prevent use-after-free
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer?.sublayers = nil
    }
}
