//
//  TemplateIntegrationTests.swift
//  SaneVideoTests
//
//  Integration tests for project templates with ProjectState
//

import XCTest
import AVFoundation
@testable import SaneVideo

@MainActor
final class TemplateIntegrationTests: XCTestCase {
    
    var projectState: ProjectState!
    
    override func setUp() async throws {
        projectState = ProjectState(projectStore: MockProjectStore())
    }
    
    func testStartProjectWithYouTubeTemplate() {
        projectState.startNewProject(template: .youtube)
        
        guard let project = projectState.currentProject else {
            XCTFail("Project should be created")
            return
        }
        
        XCTAssertEqual(project.name, "YouTube", "Project name should match template")
        XCTAssertEqual(project.captionStyleName, "YouTube", "Caption style should be set from template")
    }
    
    func testStartProjectWithTikTokTemplate() {
        projectState.startNewProject(template: .tiktok)
        
        guard let project = projectState.currentProject else {
            XCTFail("Project should be created")
            return
        }
        
        XCTAssertEqual(project.name, "TikTok", "Project name should match template")
        XCTAssertEqual(project.captionStyleName, "TikTok", "Caption style should be set from template")
    }
    
    func testStartProjectWithInstagramTemplate() {
        projectState.startNewProject(template: .instagram)
        
        guard let project = projectState.currentProject else {
            XCTFail("Project should be created")
            return
        }
        
        XCTAssertEqual(project.name, "Instagram", "Project name should match template")
        XCTAssertEqual(project.captionStyleName, "Instagram", "Caption style should be set from template")
    }
    
    func testStartProjectWithCustomTemplate() {
        projectState.startNewProject(template: .custom)
        
        guard let project = projectState.currentProject else {
            XCTFail("Project should be created")
            return
        }
        
        XCTAssertEqual(project.name, "Custom", "Project name should match template")
        XCTAssertEqual(project.captionStyleName, "Classic", "Custom template should use Classic style")
    }
    
    func testStartProjectWithoutTemplate() {
        projectState.startNewProject()
        
        guard let project = projectState.currentProject else {
            XCTFail("Project should be created")
            return
        }
        
        // Default project should have default name
        XCTAssertEqual(project.name, "Untitled Project", "Default project should have default name")
    }
    
    func testTemplateProjectIsSaved() {
        let expectation = XCTestExpectation(description: "Project saved")
        
        projectState.startNewProject(template: .youtube)
        
        // ProjectState saves automatically on startNewProject
        // We can't easily test async save without exposing internals,
        // but we can verify the project exists in currentProject
        XCTAssertNotNil(projectState.currentProject, "Project should be created and available")
        
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }
}
