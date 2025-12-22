//
//  WaveformView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let color: Color = .blue

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2

                let count = samples.count
                if count == 0 { return }

                let stepX = width / CGFloat(count)

                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) * stepX
                    let amplitude = CGFloat(sample) * (height / 2) * 0.9 // 90% height scale

                    path.move(to: CGPoint(x: x, y: midY - amplitude))
                    path.addLine(to: CGPoint(x: x, y: midY + amplitude))
                }
            }
            .stroke(color.opacity(0.6), lineWidth: 1)
        }
        .allowsHitTesting(false) // Don't block clicks from clip
    }
}
