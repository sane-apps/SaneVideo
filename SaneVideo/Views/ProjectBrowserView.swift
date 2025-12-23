//
//  ProjectBrowserView.swift
//  SaneVideo
//
//  Created by SaneVideo Refactor
//

import SwiftUI

struct ProjectBrowserView: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss

    @State private var hoveredProjectId: UUID?

    // Rename state
    @State private var projectToRename: VideoProject?
    @State private var newName: String = ""
    @State private var isRenaming = false

    // Delete state
    @State private var projectToDelete: VideoProject?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "browser.header", defaultValue: "Projects"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Menu {
                    ForEach(ProjectTemplate.allTemplates) { template in
                        Button(action: {
                            appState.projectState.startNewProject(template: template)
                            dismiss()
                        }, label: {
                            Label(template.name, systemImage: template.icon)
                        })
                        .accessibilityIdentifier("browser.template.\(template.id)")
                    }
                } label: {
                    Label(String(localized: "browser.action.new", defaultValue: "New Project"), systemImage: "plus")
                }
                .accessibilityIdentifier("browser.new_project")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Template Selection Section
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "browser.templates.header", defaultValue: "Choose a Template"))
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(ProjectTemplate.allTemplates) { template in
                            TemplateCard(template: template) {
                                appState.projectState.startNewProject(template: template)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.vertical, 8)
            }

            // Grid or List
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 16)], spacing: 16) {
                    // Projects
                    ForEach(appState.projectState.projects) { project in
                        ProjectCard(
                            project: project,
                            isCurrent: appState.projectState.currentProject?.id == project.id,
                            onSelect: {
                                appState.projectState.currentProject = project
                                dismiss()
                            },
                            onRename: {
                                projectToRename = project
                                newName = project.name
                                isRenaming = true
                            },
                            onDelete: {
                                projectToDelete = project
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        // Rename Alert
        .alert(String(localized: "browser.rename.title", defaultValue: "Rename Project"), isPresented: $isRenaming) {
            TextField(String(localized: "browser.rename.placeholder", defaultValue: "Project Name"), text: $newName)
                .accessibilityIdentifier("browser.rename_field")
            Button(String(localized: "browser.action.rename", defaultValue: "Rename")) {
                if let project = projectToRename {
                    if appState.projectState.currentProject?.id == project.id {
                        appState.projectState.renameProject(newName)
                    } else {
                        appState.projectState.currentProject = project
                        appState.projectState.renameProject(newName)
                    }
                }
            }
            .accessibilityIdentifier("browser.rename_submit")
            Button(String(localized: "browser.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            if let name = projectToRename?.name {
                Text(String(localized: "browser.rename.message", defaultValue: "Enter a new name for project") + ": '\(name)'")
            }
        }

        // Delete Alert
        .confirmationDialog(
            String(localized: "browser.delete.title", defaultValue: "Are you sure you want to delete this project?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let name = projectToDelete?.name {
                Button(String(localized: "browser.action.delete", defaultValue: "Delete") + " '\(name)'", role: .destructive) {
                    if let project = projectToDelete {
                        appState.projectState.deleteProject(project)
                    }
                }
                .accessibilityIdentifier("browser.delete_confirm")
            }
            Button(String(localized: "browser.action.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "browser.delete.message", defaultValue: "This action cannot be undone."))
        }
    }
}

struct TemplateCard: View {
    let template: ProjectTemplate
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.system(size: 32))
                    .foregroundColor(Color(template.color))
                    .frame(width: 60, height: 60)
                    .background(Color(template.color).opacity(0.1))
                    .clipShape(Circle())

                VStack(spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(width: 180, height: 160)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isHovering ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("browser.template_card.\(template.id)")
        .onHover { hover in
            withAnimation(.smoothUI) {
                isHovering = hover
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.smoothUI, value: isHovering)
    }
}

struct ProjectCard: View {
    let project: VideoProject
    let isCurrent: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail / Icon Area
            ZStack {
                Color.black.opacity(0.1)

                Image(systemName: "film.stack")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)

            // Info Area
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(isCurrent ? .accentColor : .primary)

                Text(String(localized: "browser.project.edited", defaultValue: "Edited") + " \(project.modifiedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                let clipCount = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
                Text(String(localized: "browser.project.clips", defaultValue: "clips") + ": \(clipCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .accessibilityIdentifier("browser.project_card.\(project.id)")
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.5) : Color.clear), lineWidth: isCurrent ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0), radius: 4, x: 0, y: 2)
        .onTapGesture {
            onSelect()
        }
        .onHover { hover in
            withAnimation(.smoothUI) {
                isHovering = hover
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.smoothUI, value: isHovering)
        .contextMenu {
            Button(String(localized: "browser.action.open", defaultValue: "Open")) { onSelect() }
                .accessibilityIdentifier("browser.card_menu.open")
            Divider()
            Button(String(localized: "browser.action.rename_menu", defaultValue: "Rename...")) { onRename() }
                .accessibilityIdentifier("browser.card_menu.rename")
            Button(role: .destructive, action: { onDelete() }, label: {
                Label(String(localized: "browser.action.delete", defaultValue: "Delete"), systemImage: "trash")
            })
            .accessibilityIdentifier("browser.card_menu.delete")
        }
    }
}
