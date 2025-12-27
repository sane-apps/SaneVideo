//
//  ErrorDisplayView.swift
//  SaneVideo
//
//  User-friendly error display with recovery suggestions
//

import SwiftUI

/// User-friendly error display with recovery actions
struct ErrorDisplayView: View {
    let error: Error
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: errorIcon)
                    .font(.title2)
                    .foregroundColor(errorColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorTitle)
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Recovery suggestions
            if let suggestions = recoverySuggestions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Try this:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.leading, 32)
            }
            
            // Action buttons
            HStack {
                if let onRetry = onRetry {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                if showingDetails {
                    Button("Hide Details") {
                        withAnimation {
                            showingDetails = false
                        }
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button("Show Details") {
                        withAnimation {
                            showingDetails = true
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 8)
            
            // Technical details (collapsible)
            if showingDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Technical Details:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(error.localizedDescription)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
    }
    
    private var errorIcon: String {
        if let appError = error as? AppError {
            switch appError {
            case .cameraPermissionDenied, .cameraPermissionRestricted, .microphonePermissionDenied, .microphonePermissionRestricted:
                return "exclamationmark.triangle.fill"
            case .exportFailed:
                return "xmark.circle.fill"
            case .recordingEngineError:
                return "video.slash.fill"
            default:
                return "exclamationmark.triangle.fill"
            }
        }
        return "exclamationmark.triangle.fill"
    }
    
    private var errorColor: Color {
        if let appError = error as? AppError {
            switch appError {
            case .cameraPermissionDenied, .cameraPermissionRestricted, .microphonePermissionDenied, .microphonePermissionRestricted:
                return .orange
            case .exportFailed:
                return .red
            case .recordingEngineError:
                return .orange
            default:
                return .orange
            }
        }
        return .orange
    }
    
    private var errorTitle: String {
        if let appError = error as? AppError {
            return appError.userFacingTitle
        }
        return "An Error Occurred"
    }
    
    private var errorMessage: String {
        if let appError = error as? AppError {
            return appError.userFacingMessage
        }
        return error.localizedDescription
    }
    
    private var recoverySuggestions: [String]? {
        if let appError = error as? AppError {
            return appError.recoverySuggestions
        }
        return nil
    }
}

// ErrorDisplayView uses AppError extensions defined in AppError.swift
