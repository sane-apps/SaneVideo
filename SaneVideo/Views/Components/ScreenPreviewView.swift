//
//  ScreenPreviewView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import AVFoundation
import SwiftUI

@MainActor
private func cleanupPreviewLayers(for view: ScreenPreviewNSView, removeBackingLayer: Bool) {
    if let sampleLayer = view.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
        sampleLayer.flushAndRemoveImage()
    }

    view.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
    view.layer?.sublayers = nil

    if removeBackingLayer {
        view.layer = nil
        view.wantsLayer = false
    }
}

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
        cleanupPreviewLayers(for: nsView, removeBackingLayer: true)
    }
}

// CRITICAL FIX: Custom NSView subclass that cleans up sublayers on dealloc
// This is a safety net in case dismantleNSView is not called
class ScreenPreviewNSView: NSView {
    deinit {
        MainActor.assumeIsolated {
            cleanupPreviewLayers(for: self, removeBackingLayer: false)
        }
    }
}
