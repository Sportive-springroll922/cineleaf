import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CineleafCommands: Commands {
    @ObservedObject var state: EditorState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("about.menu") { openWindow(id: "about") }
        }

        CommandGroup(replacing: .newItem) {
            Button("project.new") { state.isNewProjectSheetPresented = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("project.open") { openProjectPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("project.save") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(state.project == nil)
            Button("project.save_as") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(state.project == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("media.import") { importPanel() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(state.project == nil)
            Button("media.consolidate") {
                Task { await state.consolidateProjectMedia() }
            }
            .disabled(
                state.projectURL == nil || state.project?.assets.isEmpty != false || state.consolidationProgress != nil
            )
            Divider()
            Button("export.action") { state.isExportSheetPresented = true }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(state.project?.timeline.duration == .zero)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("edit.undo") { state.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!state.canUndo)
            Button("edit.redo") { state.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.canRedo)
        }

        CommandMenu("menu.editing") {
            Button("playback.toggle") { state.playback.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Button("timeline.previous_frame") { state.nudgePlayhead(frames: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("timeline.next_frame") { state.nudgePlayhead(frames: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("timeline.previous_large_step") { state.nudgePlayhead(frames: -10) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("timeline.next_large_step") { state.nudgePlayhead(frames: 10) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Divider()
            Button("timeline.split") { state.splitSelection() }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(state.selectedClipIDs.count != 1)
            Button("timeline.duplicate") { state.duplicateSelection() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(state.selectedClipIDs.count != 1)
            Button("freeze.create") {
                guard let id = state.selectedClipIDs.first else { return }
                Task { await state.createFreezeFrame(for: id) }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(state.selectedClip?.kind != .video || state.isCreatingFreezeFrame)
            Button("timeline.delete") { state.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(state.selectedClipIDs.isEmpty)
            Button("timeline.ripple_delete") { state.rippleDeleteSelection() }
                .keyboardShortcut(.delete, modifiers: .shift)
                .disabled(state.selectedClipIDs.isEmpty)
            Divider()
            Button("timeline.group") { state.groupSelection() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(state.selectedClipIDs.count < 2)
            Button("timeline.ungroup") { state.ungroupSelection() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(state.selectedClipIDs.isEmpty)
            Button("timeline.link") { state.linkSelection() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(state.selectedClipIDs.count < 2)
            Button("timeline.add_marker") { state.addMarker() }
                .keyboardShortcut("m", modifiers: [])
                .disabled(state.project == nil)
            Divider()
            Button("timeline.zoom_in") { state.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("timeline.zoom_out") { state.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("timeline.go_start") { state.goToStart() }
                .keyboardShortcut(.home, modifiers: [])
            Button("timeline.go_end") { state.goToEnd() }
                .keyboardShortcut(.end, modifiers: [])
        }
    }

    private func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "project.open")
        panel.allowedContentTypes = [UTType(importedAs: "org.cineleaf.project")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.open(url) }
    }

    private func save() {
        if state.projectURL == nil { saveAs(); return }
        Task { _ = await state.save() }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.title = String(localized: "project.save_as")
        panel.allowedContentTypes = [UTType(exportedAs: "org.cineleaf.project")]
        panel.nameFieldStringValue = (state.project?.name ?? String(localized: "project.untitled")) + ".cineleaf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { _ = await state.saveAs(url) }
    }

    private func importPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "media.import")
        panel.allowedContentTypes = [.movie, .audio, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        Task { await state.importMedia(panel.urls) }
    }
}
