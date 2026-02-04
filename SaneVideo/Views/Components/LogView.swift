//
//  LogView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import OSLog
import SwiftUI

struct LogView: View {
    private var logManager = ServiceContainer.shared.logManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "logs.header.title", defaultValue: "Application Logs"))
                    .font(.headline)
                Spacer()

                Button(String(localized: "logs.action.done", defaultValue: "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("logs.action.done")

                Button(String(localized: "logs.action.clear", defaultValue: "Clear")) {
                    logManager.clearLogs()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .accessibilityIdentifier("logs.action.clear")

                Button(String(localized: "logs.action.copy_all", defaultValue: "Copy All")) {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logManager.exportLogs(), forType: .string)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor)
                .cornerRadius(6)
                .accessibilityIdentifier("logs.action.copy_all")
                
                Button(String(localized: "logs.action.export", defaultValue: "Export to File")) {
                    Task {
                        do {
                            let url = try ServiceContainer.shared.logExportService.exportRecentLogs()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            ServiceContainer.shared.toastManager.show(String(localized: "logs.error.export_failed", defaultValue: "Log export failed"), type: .error)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .cornerRadius(6)
                .accessibilityIdentifier("logs.action.export")
            }
            .padding()
            .background(Color.black.opacity(0.2))

            // Log List
            ScrollViewReader { proxy in
                List {
                    ForEach(logManager.logs) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                            .accessibilityIdentifier("logs.entry.\(entry.id)")
                    }
                }
                .onAppear {
                    // Scroll to bottom on appear
                    if let last = logManager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct LogEntryRow: View {
    let entry: LogManager.LogEntry

    var color: Color {
        switch entry.level {
        case .fault, .error: .red
        case .info: .blue
        case .debug: .gray
        default: .primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.levelEmoji)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.date, style: .time)
                        .font(.caption2)
                        .foregroundColor(Color.stone)

                    Text(entry.category)
                        .font(.caption2.bold())
                        .foregroundColor(Color.stone)
                        .padding(.horizontal, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Dimensions.cornerRadius))
                }

                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(color)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}
