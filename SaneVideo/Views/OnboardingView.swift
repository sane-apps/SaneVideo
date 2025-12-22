//
//  OnboardingView.swift
//  SaneVideo
//
//  First-run onboarding experience
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @Bindable var permissionManager = ServiceContainer.shared.permissionManager
    @State private var isRequestingPermissions = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to SaneVideo",
            subtitle: "Professional screen recording made simple",
            icon: "video.fill",
            color: .blue,
            features: [
                "Record your screen and camera simultaneously",
                "Edit with powerful timeline tools",
                "Export in 4K with HEVC compression"
            ]
        ),
        OnboardingPage(
            title: "Record Anything",
            subtitle: "Capture your screen, camera, or both",
            icon: "record.circle",
            color: .red,
            features: [
                "⌥⌘R - Start/stop recording globally",
                "Picture-in-Picture camera overlay",
                "Live audio level monitoring"
            ]
        ),
        OnboardingPage(
            title: "Smart Editing",
            subtitle: "AI-powered editing features",
            icon: "wand.and.stars",
            color: .purple,
            features: [
                "Remove silence automatically",
                "Remove filler words (um, uh)",
                "Generate captions with one click"
            ]
        ),
        OnboardingPage(
            title: "Export & Share",
            subtitle: "Professional output in seconds",
            icon: "square.and.arrow.up",
            color: .green,
            features: [
                "1080p or 4K resolution",
                "HEVC or H.264 encoding",
                "Export transcripts as PDF"
            ]
        ),
        OnboardingPage(
            title: "Permissions",
            subtitle: "We need a few permissions to get started",
            icon: "lock.shield",
            color: .orange,
            features: [
                "Camera - For recording video",
                "Microphone - For recording audio",
                "Screen Recording - For screen capture"
            ],
            isPermissionPage: true
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page Content
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 350)

            // Page Indicators
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 16)

            // Navigation Buttons
            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button(String(localized: "action.back", defaultValue: "Back")) {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("onboarding.action.back")
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button(String(localized: "action.next", defaultValue: "Next")) {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.action.next")
                } else {
                    if pages[currentPage].isPermissionPage ?? false {
                        Button(action: requestPermissions) {
                            HStack {
                                if isRequestingPermissions {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                }
                                Text(isRequestingPermissions ? String(localized: "action.requesting", defaultValue: "Requesting...") : String(localized: "action.grant_permissions", defaultValue: "Grant Permissions"))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRequestingPermissions)
                        .accessibilityIdentifier("onboarding.action.grant_permissions")
                    } else {
                        Button(String(localized: "action.get_started", defaultValue: "Get Started")) {
                            completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("onboarding.action.get_started")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 480)
        .background(.ultraThinMaterial)
    }

    private func requestPermissions() {
        isRequestingPermissions = true
        Task {
            // Request all permissions sequentially
            _ = await permissionManager.requestCameraPermission()
            _ = await permissionManager.requestMicrophonePermission()
            
            await MainActor.run {
                // Request screen recording permission
                if permissionManager.screenRecordingStatus == .denied {
                    permissionManager.openScreenRecordingSettings()
                } else if permissionManager.screenRecordingStatus == .notDetermined {
                    permissionManager.requestScreenRecordingPermission()
                }
                
                isRequestingPermissions = false
                // Auto-advance to next page or complete
                if currentPage < pages.count - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    completeOnboarding()
                }
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }
}

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let features: [String]
    let isPermissionPage: Bool?

    init(title: String, subtitle: String, icon: String, color: Color, features: [String], isPermissionPage: Bool? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.features = features
        self.isPermissionPage = isPermissionPage
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    var permissionManager = ServiceContainer.shared.permissionManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: page.icon)
                .font(.system(size: 60))
                .foregroundStyle(
                    .linearGradient(
                        colors: [page.color, page.color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 30)

            Text(page.title)
                .font(.title.bold())

            Text(page.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if page.isPermissionPage == true {
                VStack(alignment: .leading, spacing: 16) {
                    PermissionStatusRow(
                        name: "Camera",
                        status: permissionManager.cameraStatus,
                        icon: "camera.fill"
                    )
                    .accessibilityIdentifier("CameraPermissionRow")
                    
                    PermissionStatusRow(
                        name: "Microphone",
                        status: permissionManager.microphoneStatus,
                        icon: "mic.fill"
                    )
                    .accessibilityIdentifier("MicrophonePermissionRow")
                    
                    PermissionStatusRow(
                        name: "Screen Recording",
                        status: permissionManager.screenRecordingStatus,
                        icon: "rectangle.inset.filled"
                    )
                    .accessibilityIdentifier("ScreenRecordingPermissionRow")
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.features, id: \.self) { feature in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(page.color)
                            Text(feature)
                                .font(.body)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
            }

            Spacer()
        }
    }
}

struct PermissionStatusRow: View {
    let name: String
    let status: PermissionStatus
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(statusColor)
                .frame(width: 24)

            Text(name)
                .font(.body)

            Spacer()

            statusIcon
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .orange
        case .unknown: return .gray
        }
    }

    private var statusIcon: some View {
        Group {
            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .denied, .restricted:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .notDetermined:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.orange)
            case .unknown:
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
