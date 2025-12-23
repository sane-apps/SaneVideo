//
//  StateChangePipeline.swift
//  SaneVideo
//
//  Unified state change pipeline to reduce complexity and improve performance
//

import Combine
import SwiftUI

// Import Combine for AnyCancellable

/// Unified state change coordinator to replace multiple onChange handlers
@MainActor
@Observable
class StateChangeCoordinator {
    private var cancellables = Set<AnyCancellable>()
    private let debounceInterval: TimeInterval = 0.15
    
    // MARK: - Project State Changes
    
    struct ProjectChange {
        let projectId: UUID?
        let tracksChanged: Bool
        let project: VideoProject?
    }
    
    private let projectChangeSubject = PassthroughSubject<ProjectChange, Never>()
    
    var projectChanges: AnyPublisher<ProjectChange, Never> {
        projectChangeSubject
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Clip Changes
    
    private let clipAddedSubject = PassthroughSubject<VideoProject, Never>()
    
    var clipAdded: AnyPublisher<VideoProject, Never> {
        clipAddedSubject
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Methods
    
    func notifyProjectIdChanged(_ projectId: UUID?, project: VideoProject?) {
        projectChangeSubject.send(ProjectChange(
            projectId: projectId,
            tracksChanged: false,
            project: project
        ))
    }
    
    func notifyTracksChanged(_ project: VideoProject?) {
        projectChangeSubject.send(ProjectChange(
            projectId: project?.id,
            tracksChanged: true,
            project: project
        ))
    }
    
    func notifyClipAdded(_ project: VideoProject) {
        clipAddedSubject.send(project)
    }
}

/// ViewModifier that handles unified state changes
struct UnifiedStateChangeModifier: ViewModifier {
    @Environment(AppState.self) var appState
    @State private var coordinator = StateChangeCoordinator()
    @State private var cancellables = Set<AnyCancellable>()
    
    func body(content: Content) -> some View {
        content
            .task {
                setupStateChangeHandlers()
            }
            .onChange(of: appState.projectState.currentProject?.id) { _, newId in
                coordinator.notifyProjectIdChanged(newId, project: appState.projectState.currentProject)
            }
            .onChange(of: appState.projectState.currentProject?.timeline.tracks) { _, _ in
                coordinator.notifyTracksChanged(appState.projectState.currentProject)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .clipAddedToTimeline)
            ) { notification in
                if let project = notification.object as? VideoProject {
                    coordinator.notifyClipAdded(project)
                }
            }
    }
    
    private func setupStateChangeHandlers() {
        coordinator.projectChanges
            .sink { change in
                handleProjectChange(change)
            }
            .store(in: &cancellables)
        
        coordinator.clipAdded
            .sink { project in
                handleClipAdded(project)
            }
            .store(in: &cancellables)
    }
    
    private func handleProjectChange(_ change: StateChangeCoordinator.ProjectChange) {
        if change.projectId != nil && !change.tracksChanged {
            // Project identity changed - reset and load
            appState.playbackState.reset()
            if let project = change.project {
                appState.playbackState.loadProject(project, forceReload: true)
            }
        } else if change.tracksChanged {
            // Tracks changed - reload player
            if let project = change.project {
                appState.playbackState.loadProject(project)
                appState.projectState.saveProject(project)
            }
        }
    }
    
    private func handleClipAdded(_ project: VideoProject) {
        // Hash debounce in PlaybackState prevents duplicates
        appState.playbackState.loadProject(project)
    }
}

extension View {
    /// Applies unified state change handling
    func withUnifiedStateChanges() -> some View {
        modifier(UnifiedStateChangeModifier())
    }
}

