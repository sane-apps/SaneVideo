//
//  TeleprompterWindow.swift
//  SaneVideo
//
//  A floating, excluded-from-capture teleprompter window for local-only demos.
//

import AppKit
import SwiftUI

final class TeleprompterWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 900, height: 320)

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        setupWindow()
        centerOnScreen()
    }

    private func setupWindow() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        contentView = NSHostingView(
            rootView: TeleprompterOverlayView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(ServiceContainer.shared.appState)
        )
    }

    private func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - (frame.width / 2)
        let y = visible.maxY - frame.height - 80
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct TeleprompterOverlayView: View {
    @Environment(AppState.self) private var appState

    @State private var contentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isAutoScrolling = false

    private var projectName: String {
        appState.currentProject?.name ?? "Untitled Project"
    }

    private var notes: SpeakerNotes {
        appState.currentProject?.speakerNotes ?? .init()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(max(notes.opacity, 0.35)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 18) {
                    header

                    GeometryReader { reader in
                        ZStack(alignment: .top) {
                            Color.clear

                            Text(notes.hasContent ? notes.text : "Add speaker notes in Demo Studio to use the teleprompter.")
                                .font(.system(size: notes.fontSize, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: reader.size.width * notes.widthFraction, alignment: .leading)
                                .scaleEffect(x: notes.isMirrored ? -1 : 1, y: 1)
                                .offset(y: scrollOffset)
                                .background(
                                    GeometryReader { textGeo in
                                        Color.clear.preference(
                                            key: TeleprompterContentHeightKey.self,
                                            value: textGeo.size.height
                                        )
                                    }
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .onAppear {
                            visibleHeight = reader.size.height
                        }
                        .onChange(of: reader.size.height) { _, newValue in
                            visibleHeight = newValue
                        }
                    }
                }
                .padding(24)
            }
            .padding(12)
            .background(Color.clear)
            .onPreferenceChange(TeleprompterContentHeightKey.self) { contentHeight = $0 }
            .onChange(of: notes.text) { _, _ in
                resetScroll()
            }
            .onChange(of: notes.fontSize) { _, _ in
                resetScroll()
            }
            .onChange(of: notes.scrollSpeed) { _, _ in
                if isAutoScrolling {
                    startAutoScroll()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(projectName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text("Teleprompter")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            Button {
                if isAutoScrolling {
                    resetScroll()
                } else {
                    startAutoScroll()
                }
            } label: {
                Label(
                    isAutoScrolling ? "Stop" : "Scroll",
                    systemImage: isAutoScrolling ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!notes.hasContent)

            Button {
                resetScroll()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Button {
                appState.toggleTeleprompter()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }

    private func startAutoScroll() {
        guard notes.hasContent else { return }

        let travelDistance = max(contentHeight - visibleHeight + 40, 0)
        guard travelDistance > 0 else { return }

        resetScroll()
        isAutoScrolling = true

        let pointsPerSecond = CGFloat(max(notes.scrollSpeed, 10))
        let duration = Double(travelDistance / pointsPerSecond)

        withAnimation(.linear(duration: duration)) {
            scrollOffset = -travelDistance
        }
    }

    private func resetScroll() {
        isAutoScrolling = false
        withAnimation(.easeOut(duration: 0.2)) {
            scrollOffset = 0
        }
    }
}

private struct TeleprompterContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
