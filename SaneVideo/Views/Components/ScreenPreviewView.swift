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

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.layer = CALayer()
        view.wantsLayer = true

        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspect

        view.layer?.addSublayer(previewLayer)
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = nsView.bounds
        }
    }
}
