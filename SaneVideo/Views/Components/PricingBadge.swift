//
//  PricingBadge.swift
//  SaneVideo
//
//  UI component for displaying pricing information
//

import SwiftUI

/// Badge showing current pricing information
struct PricingBadge: View {
    @Environment(PricingConfiguration.self) var pricingConfig
    
    var body: some View {
        if pricingConfig.isLaunchPeriod {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text(pricingConfig.currentPrice)
                    .font(.caption.bold())
                Text("Launch")
                    .font(.caption2)
                    .foregroundColor(Color.stone)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundColor(.white)
        } else {
            HStack(spacing: 4) {
                Text(pricingConfig.currentPrice)
                    .font(.caption.bold())
                Text("MIT")
                    .font(.caption2)
                    .foregroundColor(Color.stone)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

/// Value proposition display
struct ValuePropositionView: View {
    @Environment(PricingConfiguration.self) var pricingConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pricingConfig.valueProposition())
                .font(.headline)
                .foregroundColor(.primary)
            
            if pricingConfig.isLaunchPeriod {
                HStack(spacing: 8) {
                    Text(pricingConfig.pricingMessage())
                        .font(.subheadline)
                        .foregroundColor(Color.stone)
                    
                    Spacer()
                    
                    PricingBadge()
                }
            } else {
                Text(pricingConfig.pricingMessage())
                    .font(.subheadline)
                    .foregroundColor(Color.stone)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(Theme.Dimensions.cornerRadius)
    }
}
