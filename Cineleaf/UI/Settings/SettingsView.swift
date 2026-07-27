import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("settings.general", systemImage: "gearshape") }
            CacheSettingsView()
                .tabItem { Label("settings.cache", systemImage: "internaldrive") }
            DiagnosticsSettingsView()
                .tabItem { Label("settings.diagnostics", systemImage: "gauge.with.dots.needle.50percent") }
        }
        .frame(width: 560, height: 360)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var language: LanguageSettings

    var body: some View {
        Form {
            Section("settings.general") {
                Picker("settings.language", selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { value in
                        Text(LocalizedStringKey(value.localizationKey)).tag(value)
                    }
                }
                Text("settings.language.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("settings.privacy") {
                Label("settings.privacy.local", systemImage: "lock.shield")
                Text("settings.privacy.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct CacheSettingsView: View {
    @EnvironmentObject private var state: EditorState
    @State private var size: Int64 = 0
    @State private var isWorking = false

    var body: some View {
        Form {
            Section("settings.cache") {
                LabeledContent("settings.cache.size") {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }
                Text("settings.cache.detail")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("settings.cache.clear", role: .destructive) { clear() }
                    .disabled(isWorking || size == 0)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await refresh() }
    }

    private func clear() {
        isWorking = true
        Task {
            defer { isWorking = false }
            try? await state.clearCache()
            await refresh()
        }
    }

    private func refresh() async {
        size = (try? await state.cacheSize()) ?? 0
    }
}

private struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var state: EditorState
    @State private var events: [DiagnosticEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.diagnostics.detail")
                .font(.caption)
                .foregroundStyle(.secondary)
            List(events) { event in
                HStack {
                    Text(LocalizedStringKey(event.localizationKey))
                    Spacer()
                    Text(event.milliseconds, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("settings.diagnostics.milliseconds")
                        .foregroundStyle(.secondary)
                }
            }
            Button("settings.diagnostics.refresh") {
                Task { events = await state.diagnosticEvents() }
            }
        }
        .padding()
        .task { events = await state.diagnosticEvents() }
    }
}

private extension DiagnosticEvent {
    var localizationKey: String {
        let supported = [
            "autosave", "composition_rebuild", "export", "media_import", "project_open",
            "project_save", "thumbnail_generation", "waveform_generation"
        ]
        return supported.contains(category)
            ? "settings.diagnostics.category.\(category)"
            : "settings.diagnostics.category.other"
    }
}
