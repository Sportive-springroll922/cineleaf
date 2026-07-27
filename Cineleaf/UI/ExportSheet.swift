import AppKit
import CineleafCore
import SwiftUI
import UniformTypeIdentifiers

struct SavedExportPreset: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var preferences: ExportPreferences
}

@MainActor
final class ExportPresetStore: ObservableObject {
    @Published private(set) var presets: [SavedExportPreset]
    private let defaults: UserDefaults
    private let key = "savedExportPresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([SavedExportPreset].self, from: $0) } ?? []
    }

    func save(name: String, preferences: ExportPreferences) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }) {
            presets[index].preferences = preferences
        } else {
            presets.append(SavedExportPreset(id: UUID(), name: cleanName, preferences: preferences))
            presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        persist()
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: key) }
    }
}

@MainActor
private final class ExportViewModel: ObservableObject {
    enum Status {
        case idle
        case success(URL)
        case failure(String)
    }

    @Published var filename = ""
    @Published var resolution = ExportResolutionPreset.p1080
    @Published var frameRate = ProjectFrameRate.fps30
    @Published var quality = ExportQuality.balanced
    @Published var codec = ExportCodec.h264
    @Published var container = ExportContainer.mp4
    @Published var progress = 0.0
    @Published var isExporting = false
    @Published var status = Status.idle
    private var task: Task<Void, Never>?

    var preferences: ExportPreferences {
        ExportPreferences(
            resolution: resolution,
            frameRate: frameRate,
            quality: quality,
            codec: codec,
            container: container
        )
    }

    func load(_ project: CineleafProject) {
        filename = project.name
        resolution = project.exportPreferences.resolution
        frameRate = project.exportPreferences.frameRate
        quality = project.exportPreferences.quality
        codec = project.exportPreferences.codec
        container = project.exportPreferences.container
    }

    func apply(_ preferences: ExportPreferences) {
        resolution = preferences.resolution
        frameRate = preferences.frameRate
        quality = preferences.quality
        codec = preferences.codec
        container = preferences.container
    }

    func start(state: EditorState, project: CineleafProject) {
        let selectedPreferences = preferences
        let plan: ExportPlan
        do {
            plan = try ExportPlan(filename: filename, project: project, preferences: selectedPreferences)
        } catch {
            status = .failure(String(describing: error))
            return
        }
        let panel = NSSavePanel()
        panel.title = String(localized: "export.destination")
        panel.allowedContentTypes = [container == .mp4 ? .mpeg4Movie : .quickTimeMovie]
        panel.nameFieldStringValue = plan.filename + (container == .mp4 ? ".mp4" : ".mov")
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        state.updateExportPreferences(selectedPreferences)
        progress = 0
        status = .idle
        isExporting = true
        task = Task { [weak self] in
            guard let self else { return }
            guard let rendered = await state.prepareExport() else {
                self.isExporting = false
                return
            }
            do {
                let result = try await state.export(
                    rendered: rendered,
                    plan: plan,
                    destination: destination
                ) { value in
                    Task { @MainActor [weak self] in self?.progress = value }
                }
                self.progress = 1
                self.status = .success(result.url)
            } catch is CancellationError {
                self.status = .idle
            } catch ExportError.cancelled {
                self.status = .idle
            } catch {
                self.status = .failure(String(describing: error))
            }
            self.isExporting = false
        }
    }

    func cancel(state: EditorState) {
        task?.cancel()
        Task { await state.cancelExport() }
    }
}

struct ExportSheet: View {
    @EnvironmentObject private var state: EditorState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ExportViewModel()
    @StateObject private var presetStore = ExportPresetStore()
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("export.title")
                .font(.title2.weight(.semibold))
            Form {
                Section("export.presets") {
                    if !presetStore.presets.isEmpty {
                        Menu("export.preset_load") {
                            ForEach(presetStore.presets) { preset in
                                Button(preset.name) {
                                    model.apply(preset.preferences)
                                    presetName = preset.name
                                }
                            }
                        }
                        Menu("export.preset_delete") {
                            ForEach(presetStore.presets) { preset in
                                Button(preset.name, role: .destructive) { presetStore.delete(preset.id) }
                            }
                        }
                    }
                    HStack {
                        TextField("export.preset_name", text: $presetName)
                        Button("export.preset_save") {
                            presetStore.save(name: presetName, preferences: model.preferences)
                        }
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                TextField("export.filename", text: $model.filename)
                Picker("export.resolution", selection: $model.resolution) {
                    Text("720p").tag(ExportResolutionPreset.p720)
                    Text("1080p").tag(ExportResolutionPreset.p1080)
                    Text("1440p").tag(ExportResolutionPreset.p1440)
                    Text("4K").tag(ExportResolutionPreset.p2160)
                }
                Picker("export.frame_rate", selection: $model.frameRate) {
                    ForEach(ProjectFrameRate.allCases, id: \.self) { rate in
                        Text("\(rate.displayValue) fps").tag(rate)
                    }
                }
                Picker("export.quality", selection: $model.quality) {
                    ForEach(ExportQuality.allCases, id: \.self) { quality in
                        Text(quality.localizationKey).tag(quality)
                    }
                }
                Picker("export.codec", selection: $model.codec) {
                    Text("H.264").tag(ExportCodec.h264)
                    Text("HEVC").tag(ExportCodec.hevc)
                }
                Picker("export.container", selection: $model.container) {
                    Text("MP4").tag(ExportContainer.mp4)
                    Text("MOV").tag(ExportContainer.mov)
                }
                if let project = state.project,
                   let plan = try? ExportPlan(
                    filename: model.filename,
                    project: project,
                    preferences: model.preferences
                   ) {
                    LabeledContent("export.configuration") {
                        Text("\(plan.resolution.width) × \(plan.resolution.height) · \(plan.frameRate.numerator) fps · \(plan.codec == .h264 ? "H.264" : "HEVC")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(model.isExporting)

            if model.isExporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: model.progress)
                    Text(model.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            switch model.status {
            case .idle:
                EmptyView()
            case .success(let url):
                HStack {
                    Label("export.success", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("export.show_in_finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            case .failure(let detail):
                DisclosureGroup("export.failure") {
                    Text(detail)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .foregroundStyle(.red)
            }

            HStack {
                if model.isExporting {
                    Button("action.cancel") { model.cancel(state: state) }
                }
                Spacer()
                Button("action.close") { dismiss() }
                    .disabled(model.isExporting)
                Button("export.action") {
                    if let project = state.project { model.start(state: state, project: project) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isExporting || state.project?.timeline.duration == .zero)
                .accessibilityIdentifier("export.start")
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear { if let project = state.project { model.load(project) } }
        .interactiveDismissDisabled(model.isExporting)
    }
}

private extension ExportQuality {
    var localizationKey: LocalizedStringKey {
        switch self {
        case .compact: "export.quality.compact"
        case .balanced: "export.quality.balanced"
        case .high: "export.quality.high"
        }
    }
}
