//
//  ProjectRegressionTests.swift
//  SaneVideoTests
//
//  Created by SaneVideo Refactor
//

import XCTest

@testable import SaneVideo

final class ProjectRegressionTests: XCTestCase {

  // MARK: - Bug Fix: Project Persistence

  // Regression Test for: "Project file corruption" prevention
  func testProjectPersistenceSanity() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let projectFile = tempDir.appendingPathComponent("RegressionTest.svproj")

    let project = VideoProject(id: UUID(), name: "Test Save", createdAt: Date())

    // Save
    let data = try JSONEncoder().encode(project)
    try data.write(to: projectFile)

    // Load
    let loadedData = try Data(contentsOf: projectFile)
    let loadedProject = try JSONDecoder().decode(VideoProject.self, from: loadedData)

    XCTAssertEqual(project.id, loadedProject.id)
    XCTAssertEqual(project.name, loadedProject.name)

    // Cleanup
    try? FileManager.default.removeItem(at: projectFile)
  }
}
