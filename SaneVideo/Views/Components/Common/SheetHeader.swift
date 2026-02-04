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
    let dismissAction: () -> Void
    let accessibilityID: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.stone)
            }
            Spacer()
            Button {
                dismissAction()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.stone)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(accessibilityID)
        }
        .padding(16)
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
