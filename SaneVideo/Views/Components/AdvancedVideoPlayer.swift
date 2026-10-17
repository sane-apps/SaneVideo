import AVKit
import SwiftUI

struct AdvancedVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player

        // MARK: - Apple Silicon Optimization

        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = true

        playerView.updatesNowPlayingInfoCenter = false

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context _: Context) {
        if nsView.player != player {
            nsView.player = player
        }
    }

    // Disconnect player when view is torn down to prevent use-after-free
    // The AVPlayerView can outlive the AVPlayer, causing crashes during autorelease
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}
