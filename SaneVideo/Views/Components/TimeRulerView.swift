//
//  TimeRulerView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import CoreGraphics
import SwiftUI

struct TimeRulerView: View {
    let duration: TimeInterval
    let pixelsPerSecond: CGFloat
    var onSeek: ((TimeInterval) -> Void)?

    // Configuration
    private let majorTickHeight: CGFloat = 20
    private let minorTickHeight: CGFloat = 10
    private let labelFontSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // Draw background
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color.secondary.opacity(0.1)))

            // Draw bottom border
            let borderPath = Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width, y: height))
            }
            context.stroke(borderPath, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)

            // Calculate ticks
            // Major tick every 1 second (50px)
            // Minor tick every 0.2 seconds (10px)
            // Label every 5 seconds (250px)

            let totalSeconds = Int(ceil(duration)) + 5 // Add buffer

            for second in 0 ... totalSeconds {
                let x = CGFloat(second) * pixelsPerSecond

                // Don't draw beyond width
                if x > width { break }

                // Draw Major Tick
                let majorPath = Path { path in
                    path.move(to: CGPoint(x: x, y: height - majorTickHeight))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                context.stroke(majorPath, with: .color(Color.secondary), lineWidth: 1)

                // Draw Label - adaptive based on zoom level
                // When zoomed in (high pixelsPerSecond), show more frequent labels
                let labelInterval: Int
                if pixelsPerSecond > 100 {
                    labelInterval = 1  // Every second when very zoomed in
                } else if pixelsPerSecond > 50 {
                    labelInterval = 2  // Every 2 seconds when moderately zoomed
                } else {
                    labelInterval = 5  // Every 5 seconds at normal/zoomed out
                }

                if second % labelInterval == 0 {
                    let timeString = formatTime(TimeInterval(second))
                    let text = Text(timeString)
                        .font(.system(size: labelFontSize))
                        .foregroundColor(.secondary)

                    context.draw(text, at: CGPoint(x: x + 5, y: height - majorTickHeight - 8), anchor: .leading)
                }

                // Draw Minor Ticks (4 ticks between seconds)
                for i in 1 ... 4 {
                    let minorX = x + (CGFloat(i) * pixelsPerSecond / 5.0)
                    if minorX > width { break }

                    let minorPath = Path { path in
                        path.move(to: CGPoint(x: minorX, y: height - minorTickHeight))
                        path.addLine(to: CGPoint(x: minorX, y: height))
                    }
                    context.stroke(minorPath, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)
                }
            }
        }
        .frame(height: 40) // Fixed height for ruler
        .contentShape(Rectangle())
        .onTapGesture { location in
            // Click-to-seek: Calculate time from tap position
            let tappedTime = max(0, Double(location.x / pixelsPerSecond))
            onSeek?(min(tappedTime, duration))
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
