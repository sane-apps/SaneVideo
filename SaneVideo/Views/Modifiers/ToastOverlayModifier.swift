//
//  ToastOverlayModifier.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct ToastOverlayModifier: ViewModifier {
    @State private var toastMessage: String?
    @State private var showToast: Bool = false

    // Internal state for auto-hide handling
    @State private var workItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showToast, let message = toastMessage {
                    toastView(message: message)
                }
            }
            .onChange(of: ServiceContainer.shared.toastManager.toastMessage) {
                guard let message = ServiceContainer.shared.toastManager.toastMessage else { return }
                self.toastMessage = message

                // Cancel previous auto-hide if any
                self.workItem?.cancel()

                withAnimation {
                    self.showToast = true
                }

                // Auto-hide after 2 seconds
                let task = DispatchWorkItem {
                    withAnimation {
                        self.showToast = false
                    }
                }
                self.workItem = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
            }
    }

    private func toastView(message: String) -> some View {
        VStack {
            Spacer()
                .frame(height: 40) // Top padding
            HStack {
                Image(systemName: "info.circle.fill")
                Text(message)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(Theme.Dimensions.cornerRadius) // Assuming derived from Theme in MainContentView
            .shadow(radius: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 20)
            Spacer()
        }
        .zIndex(2000)
        .animation(.spring(), value: showToast)
        .allowsHitTesting(false)
    }
}

extension View {
    func withToastOverlay() -> some View {
        modifier(ToastOverlayModifier())
    }
}
