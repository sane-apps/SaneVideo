//
//  ClipTrimHandle.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI
import AppKit
import CoreMedia

/// Draggable trim handle for TimelineClipView
struct ClipTrimHandle: View {
    let isLeft: Bool
    let clipHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let clip: VideoClip
    let playheadTime: CMTime
    let snapThreshold: CGFloat

    var onTrimStart: ((CMTime) -> Void)?
    var onTrimEnd: ((CMTime) -> Void)?

    @Binding var isDragging: Bool
    @Binding var trimOffset: CGFloat

    var onHoverChange: ((Bool) -> Void)?

    var body: some View {
        ZStack {
            // Touch target - Transparent but wide for easy grabbing
            Rectangle()
                .fill(Color.accentColor.opacity(0.01))
                .frame(width: 20, height: clipHeight)

            // Visual component - Distinct "Handle"
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white)
                .frame(width: 12, height: clipHeight * 0.6)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .overlay(
                    // Grip Lines
                    HStack(spacing: 2) {
                        ForEach(0..<3) { _ in
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: 2, height: 12)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
        }
        // CRITICAL FIX: Offset handle during drag to keep it under cursor
        // This prevents the handle from moving away when the clip expands
        .offset(x: isDragging ? trimOffset : 0)
        .contentShape(Rectangle())
        .cursor(NSCursor.resizeLeftRight)
        .onHover { hovering in
            // CRITICAL FIX: Notify parent when hovering over handle
            // This prevents clip from scaling when trying to grab handle
            AppLogger.uiLog.debug("🔧 Trim handle hover: isLeft=\(isLeft), hovering=\(hovering)")
            onHoverChange?(hovering)
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    AppLogger.uiLog.info("🔧 Trim handle drag started: isLeft=\(isLeft), translation=\(value.translation.width)")
                    isDragging = true
                    trimOffset = value.translation.width
                }
                .onEnded { value in
                    AppLogger.uiLog.info("🔧 Trim handle drag ended: isLeft=\(isLeft), finalTranslation=\(value.translation.width)")
                    var deltaSeconds = value.translation.width / pixelsPerSecond

                    // SNAP TO PLAYHEAD
                    deltaSeconds = applyPlayheadSnapping(
                        deltaSeconds: deltaSeconds,
                        isLeft: isLeft
                    )

                    let delta = CMTime(seconds: deltaSeconds, preferredTimescale: 600)

                    if isLeft {
                        isDragging = false
                        let newStart = CMTimeAdd(clip.trimStart, delta)
                        let clampedStart = max(.zero, min(newStart, CMTimeSubtract(clip.trimEnd, CMTime(seconds: 0.1, preferredTimescale: 600))))
                        onTrimStart?(clampedStart)
                        trimOffset = 0
                    } else {
                        isDragging = false
                        let newEnd = CMTimeAdd(clip.trimEnd, delta)
                        let clampedEnd = min(clip.duration, max(newEnd, CMTimeAdd(clip.trimStart, CMTime(seconds: 0.1, preferredTimescale: 600))))
                        onTrimEnd?(CMTimeSubtract(clip.duration, clampedEnd))
                        trimOffset = 0
                    }
                }
        )
        .onTapGesture {
            // Do nothing - let the drag handle the interaction
        }
    }

    private func applyPlayheadSnapping(deltaSeconds: Double, isLeft: Bool) -> Double {
        var result = deltaSeconds

        if isLeft {
            let proposedTrimStart = clip.trimStart.seconds + deltaSeconds
            let playheadRelative = playheadTime.seconds - clip.startTime.seconds
            let distanceToPlayhead = abs(proposedTrimStart - playheadRelative)
            if distanceToPlayhead * pixelsPerSecond < snapThreshold {
                result = playheadRelative - clip.trimStart.seconds
            }
        } else {
            let proposedTrimEnd = clip.trimEnd.seconds + deltaSeconds
            let playheadRelative = playheadTime.seconds - clip.startTime.seconds
            let distanceToPlayhead = abs(proposedTrimEnd - playheadRelative)
            if distanceToPlayhead * pixelsPerSecond < snapThreshold {
                result = playheadRelative - clip.trimEnd.seconds
            }
        }

        return result
    }
}
