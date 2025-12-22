//
//  WaveformPlaceholderView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct WaveformPlaceholderView: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let midY = height / 2
            let barWidth: CGFloat = 2
            let spacing: CGFloat = 1
            let totalBars = Int(width / (barWidth + spacing))
            
            for i in 0..<totalBars {
                // Deterministic pseudo-random height
                let seed = Double(i) * 0.1
                let noise = abs(sin(seed * 5) * cos(seed * 2.3))
                let barHeight = CGFloat(0.2 + (noise * 0.8)) * height
                
                let rect = CGRect(
                    x: CGFloat(i) * (barWidth + spacing),
                    y: midY - (barHeight / 2),
                    width: barWidth,
                    height: barHeight
                )
                
                context.fill(Path(rect), with: .color(.green.opacity(0.6)))
            }
        }
        .background(Color.black.opacity(0.3))
    }
}
