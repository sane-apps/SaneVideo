//
//  QuickAccessOverlay.swift
//  SaneVideo
//
//  Post-recording quick access overlay with instant editing options
//  Inspired by CleanShot X's instant gratification workflow
//

import AppKit
import AVFoundation
import SwiftUI

struct QuickAccessOverlay: View {
    @Environment(AppState.self) var appState
    let recordingURL: URL
    let thumbnail: NSImage?
    let onEdit: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var isHoveringEdit = false
    @State private var isHoveringSave = false
    @State private var isHoveringShare = false
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }
            
            // Main Overlay Card
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green.gradient)
                        .symbolEffect(.bounce, value: isVisible)
                    
                    Text("Recording Complete")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("What would you like to do?")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 32)
                
                // Thumbnail Preview
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                        .smoothAppear()
                }
                
                // Action Buttons
                HStack(spacing: 16) {
                    // Edit Now (Primary)
                    QuickAccessButton(
                        icon: "scissors",
                        title: "Edit Now",
                        subtitle: "Jump to editor",
                        isPrimary: true,
                        isHovering: $isHoveringEdit
                    ) {
                        ServiceContainer.shared.hapticsManager.impact()
                        dismissWithAnimation {
                            onEdit()
                        }
                    }
                    
                    // Save for Later
                    QuickAccessButton(
                        icon: "square.and.arrow.down",
                        title: "Save",
                        subtitle: "Save for later",
                        isPrimary: false,
                        isHovering: $isHoveringSave
                    ) {
                        ServiceContainer.shared.hapticsManager.impact()
                        dismissWithAnimation {
                            onSave()
                        }
                    }
                    
                    // Share
                    QuickAccessButton(
                        icon: "square.and.arrow.up",
                        title: "Share",
                        subtitle: "Export & share",
                        isPrimary: false,
                        isHovering: $isHoveringShare
                    ) {
                        ServiceContainer.shared.hapticsManager.impact()
                        dismissWithAnimation {
                            onShare()
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .frame(width: 480)
            .background {
                // Enhanced Liquid Glass
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .opacity(0.95)
                    
                    // Premium edge lighting
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.25),
                                    .white.opacity(0.1),
                                    .clear,
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
            .shadow(color: .white.opacity(0.1), radius: 10, y: -5)
            .scaleEffect(isVisible ? 1.0 : 0.9)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.gentleSpring, value: isVisible)
        }
        .onAppear {
            // Animate in
            withAnimation(.gentleSpring.delay(0.1)) {
                isVisible = true
            }
        }
    }
    
    private func dismissWithAnimation(completion: (() -> Void)? = nil) {
        withAnimation(.smoothUI) {
            isVisible = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
            completion?()
        }
    }
}

// MARK: - Quick Access Button

struct QuickAccessButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let isPrimary: Bool
    @Binding var isHovering: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            action()
        }) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isPrimary ? .white : .primary)
                    .frame(width: 64, height: 64)
                    .background {
                        if isPrimary {
                            Circle()
                                .fill(.blue.gradient)
                                .shadow(color: .blue.opacity(0.4), radius: 10)
                        } else {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.2), radius: 10)
                        }
                    }
                    .scaleEffect(isHovering ? 1.1 : 1.0)
                    .scaleEffect(isPressed ? 0.95 : 1.0)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isHovering ? .white.opacity(0.3) : .white.opacity(0.1),
                                lineWidth: isHovering ? 1.5 : 1
                            )
                    }
            }
            .shadow(color: .black.opacity(isHovering ? 0.3 : 0.1), radius: isHovering ? 15 : 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smoothUI) {
                isHovering = hovering
            }
        }
        .pressScale()
        .smoothAppear()
    }
}

