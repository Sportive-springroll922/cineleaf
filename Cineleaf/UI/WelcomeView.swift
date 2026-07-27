import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("welcome.title")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("welcome.subtitle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("project.new") { state.isNewProjectSheetPresented = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("welcome.newProject")
                Button("project.open") { openPanel() }
                    .controlSize(.large)
                    .accessibilityIdentifier("welcome.openProject")
            }
            if !state.recentProjects.urls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("project.recent")
                            .font(.headline)
                        Spacer()
                        Button("project.recent.clear") { state.recentProjects.clear() }
                            .buttonStyle(.link)
                    }
                    ForEach(state.recentProjects.urls, id: \.path) { url in
                        Button {
                            Task { await state.open(url) }
                        } label: {
                            HStack {
                                Image(systemName: "film.stack")
                                VStack(alignment: .leading) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Text(url.deletingLastPathComponent().lastPathComponent)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: 440)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { state.recentProjects.removeMissing() }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "project.open")
        panel.allowedContentTypes = [UTType(importedAs: "org.cineleaf.project")]
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.open(url) }
    }
}
