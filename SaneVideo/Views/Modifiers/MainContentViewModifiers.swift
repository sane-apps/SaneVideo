//
//  MainContentViewModifiers.swift
//  SaneVideo
//
//  Helper modifiers to break up complex MainContentView body
//

import SwiftUI

struct UndoManagerModifier: ViewModifier {
    let appState: AppState
    let undoManager: UndoManager?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                appState.projectState.undoManager = undoManager
            }
            .onChange(of: undoManager) { _, newValue in
                appState.projectState.undoManager = newValue
            }
    }
}

struct ClipSelectionModifier: ViewModifier {
    let appState: AppState
    @Binding var selectedClip: VideoClip?
    
    func body(content: Content) -> some View {
        content
            .onChange(of: appState.recentlyAddedClip) {
                if let clip = appState.recentlyAddedClip {
                    selectedClip = clip
                }
            }
    }
}

