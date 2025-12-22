import Testing
import CoreMedia
import Foundation
import SwiftUI
@testable import SaneVideo

@Suite("Caption Tests")
@MainActor
struct CaptionTests {

    // MARK: - Draggable Captions Tests
    
    @Test("Caption offset updates correctly")
    func captionOffsetUpdates() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        #expect(projectState.currentProject?.captionOffset == .zero)
        
        let newOffset = CGSize(width: 50, height: 100)
        projectState.updateCaptionOffset(newOffset)
        
        #expect(projectState.currentProject?.captionOffset == newOffset)
    }
    
    @Test("Caption offset undo and redo behavior")
    func captionOffsetUndo() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager
        
        let initialOffset = CGSize.zero
        let newOffset = CGSize(width: 100, height: 200)
        
        #expect(projectState.currentProject?.captionOffset == initialOffset)
        
        projectState.updateCaptionOffset(newOffset)
        #expect(projectState.currentProject?.captionOffset == newOffset)
        
        undoManager.undo()
        #expect(projectState.currentProject?.captionOffset == initialOffset)
        
        undoManager.redo()
        #expect(projectState.currentProject?.captionOffset == newOffset)
    }

    // MARK: - Font Picker Tests
    
    @Test("Caption font updates and defaults")
    func captionFontUpdates() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        #expect(projectState.currentProject?.captionFontName == nil)
        
        let fontName = "Helvetica Neue"
        projectState.updateCaptionFont(fontName)
        #expect(projectState.currentProject?.captionFontName == fontName)
        
        projectState.updateCaptionFont(nil)
        #expect(projectState.currentProject?.captionFontName == nil)
    }
    
    @Test("Caption font undo behavior")
    func captionFontUndo() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        let undoManager = UndoManager()
        projectState.undoManager = undoManager
        
        let fontName = "Impact"
        
        #expect(projectState.currentProject?.captionFontName == nil)
        
        projectState.updateCaptionFont(fontName)
        #expect(projectState.currentProject?.captionFontName == fontName)
        
        undoManager.undo()
        #expect(projectState.currentProject?.captionFontName == nil)
    }
    
    // MARK: - Caption Style Logic Tests
    
    @Test("Caption style font override logic")
    func captionStyleFontOverride() {
        var project = VideoProject(name: "Test Project")
        project.captionStyleName = "Classic"
        project.captionFontName = "Papyrus"
        
        let style = project.captionStyle
        #expect(style.fontName == "Papyrus")
    }
    
    @Test("Caption style reset behavior on preset change")
    func captionStyleResetOnPresetChange() {
        let projectState = ProjectState()
        projectState.currentProject = VideoProject(name: "Test Project")
        
        projectState.updateCaptionFont("Arial")
        #expect(projectState.currentProject?.captionFontName == "Arial")
        
        var project = projectState.currentProject!
        project.captionStyleName = "Classic"
        project.captionFontName = "Arial"
        
        // Change style via the computed property SETTER
        project.captionStyle = .bold
        
        #expect(project.captionFontName == nil)
        #expect(project.captionStyleName == "Bold")
    }
}
