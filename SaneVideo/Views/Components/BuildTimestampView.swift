//
//  BuildTimestampView.swift
//  SaneVideo
//
//  Created by SaneVideo
//

import SwiftUI

/// Displays the build timestamp for cross-referencing screenshots with logs
struct BuildTimestampView: View {
  private let buildTimestamp: String

  init() {
    // Get build timestamp from executable file modification time
    // Format matches log timestamps: [2025-12-30 14:42:36]
    if let executableURL = Bundle.main.executableURL,
       let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
       let modificationDate = attributes[.modificationDate] as? Date {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      formatter.timeZone = TimeZone.current
      self.buildTimestamp = formatter.string(from: modificationDate)
    } else {
      // Fallback: use current date if we can't get executable time
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      formatter.timeZone = TimeZone.current
      self.buildTimestamp = formatter.string(from: Date())
    }
  }

  var body: some View {
    Text("Build: \(buildTimestamp)")
      .font(.system(size: 10, weight: .regular, design: .monospaced))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        RoundedRectangle(cornerRadius: 4)
          .fill(.regularMaterial)
          .opacity(0.8)
      }
      .help("Build timestamp for cross-referencing with logs")
  }
}

#Preview {
  BuildTimestampView()
    .padding()
}
