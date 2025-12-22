//
//  AdvancedVideoPlayer.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//  Optimized for Apple Silicon with AVPlayerView
//

import AVKit
import SwiftUI

/// A professional-grade video player using AVPlayerView for optimal performance on macOS
struct AdvancedVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player

        // MARK: - Apple Silicon Optimization

        // Use AVPlayerView controls style optimized for modern macOS
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = true

        // Optimize for performance
        playerView.updatesNowPlayingInfoCenter = false // We handle this manually if needed

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context _: Context) {
        // Efficiently update player only if changed
        if nsView.player != player {
            nsView.player = player
        }
    }
}
