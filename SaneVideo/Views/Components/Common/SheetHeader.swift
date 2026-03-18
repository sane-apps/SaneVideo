//
//  SheetHeader.swift
//  SaneVideo
//
//  Reusable header component for modal sheets
//

import SwiftUI

/// Standard header for export and settings sheets
struct SheetHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let dismissAction: () -> Void
    let accessibilityID: String

    init(
        title: String,
        subtitle: String,
        icon: String = "sparkles",
        dismissAction: @escaping () -> Void,
        accessibilityID: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.dismissAction = dismissAction
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Colors.accent, Theme.Colors.accentDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: Theme.Typography.iconSizeLG, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .saneReadableSectionTitle()
                    Text(subtitle)
                        .saneReadableSupportText()
                }
            }
            Spacer()
            Button {
                dismissAction()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: Theme.Typography.iconSizeLG, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(accessibilityID)
            .help(String(localized: "sheet.close.help", defaultValue: "Close"))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Theme.Colors.helperTintStrong.opacity(0.38),
                    .clear,
                    Theme.Colors.accentGlow.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

/// Standard footer for export sheets with Cancel/Action buttons
struct SheetFooter: View {
    let cancelTitle: String
    let actionTitle: String
    let isLoading: Bool
    let loadingTitle: String
    let isDisabled: Bool
    let cancelID: String
    let actionID: String
    let onCancel: () -> Void
    let onAction: () -> Void

    init(
        cancelTitle: String = String(localized: "action.cancel", defaultValue: "Cancel"),
        actionTitle: String,
        isLoading: Bool = false,
        loadingTitle: String = String(localized: "action.processing", defaultValue: "Processing..."),
        isDisabled: Bool = false,
        cancelID: String,
        actionID: String,
        onCancel: @escaping () -> Void,
        onAction: @escaping () -> Void
    ) {
        self.cancelTitle = cancelTitle
        self.actionTitle = actionTitle
        self.isLoading = isLoading
        self.loadingTitle = loadingTitle
        self.isDisabled = isDisabled
        self.cancelID = cancelID
        self.actionID = actionID
        self.onCancel = onCancel
        self.onAction = onAction
    }

    var body: some View {
        HStack {
            Button(cancelTitle) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(cancelID)

            Spacer()

            Button {
                onAction()
            } label: {
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                        Text(loadingTitle)
                    }
                } else {
                    Label(actionTitle, systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isDisabled)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(actionID)
        }
        .padding(16)
    }
}
