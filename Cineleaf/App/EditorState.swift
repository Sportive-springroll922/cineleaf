import AppKit
import AVFoundation
import Combine
import CoreGraphics
import CineleafCore

struct PresentedError: Identifiable {
    let id = UUID()
    var titleKey: String
    var messageKey: String
    var technicalDetail: String
}

@MainActor
final class EditorState: ObservableObject {
    @Published private(set) var project: CineleafProject?
    @Published private(set) var projectURL: URL?
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var selectedAssetID: UUID?
    @Published var timelineZoom: Double = 80
    @Published private(set) var isDirty = false
    @Published private(set) var isImporting = false
    @Published private(set) var isBuildingPreview = false
    @Published private(set) var waveforms: [UUID: [Float]] = [:]
    @Published private(set) var mediaAvailability: [UUID: MediaAvailability] = [:]
    @Published var presentedError: PresentedError?
    @Published var availableRecovery: CineleafProject?
    @Published var isNewProjectSheetPresented = false
    @Published var isProjectSettingsPresented = false
    @Published var isExportSheetPresented = false

    let playback = PlaybackController()
    let recentProjects = RecentProjectsStore()
    let cache = DerivedDataCache.shared

    private var editor: ProjectEditor?
    private var history = EditHistory(limit: 50)
    private let store = ProjectPackageStore()
    private let accessManager = MediaAccessManager()
    private let inspector = AVMediaInspector()
    private let thumbnailGenerator = AVThumbnailGenerator()
    private let waveformGenerator = AVWaveformGenerator()
    private lazy var compositionBuilder = AVCompositionBuilder(accessManager: accessManager)
    private let exportService = AVExportService()
    private var autosaveTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var waveformTasks: [UUID: Task<Void, Never>] = [:]
    @Published private(set) var renderedComposition: RenderedComposition?

    init() {
        Task { [weak self] in
            guard let self else { return }
            do {
                self.availableRecovery = try await self.store.availableRecoveries().first
            } catch {
                self.present(error, messageKey: "error.recovery.load")
            }
        }
    }

    deinit {
        autosaveTask?.cancel()
        previewTask?.cancel()
        waveformTasks.values.forEach { $0.cancel() }
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var selectedClip: TimelineClip? {
        guard selectedClipIDs.count == 1, let selected = selectedClipIDs.first else { return nil }
        return project?.timeline.tracks.flatMap(\.clips).first { $0.id == selected }
    }

    func newProject(name: String, preset: CanvasPreset, frameRate: ProjectFrameRate) {
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = CineleafProject(
            name: finalName.isEmpty ? String(localized: "project.untitled") : finalName,
            canvasPreset: preset,
            frameRate: frameRate
        )
        install(project, url: nil)
        isDirty = true
        scheduleAutosave()
    }

    func recover(_ project: CineleafProject) {
        install(project, url: nil)
        availableRecovery = nil
        isDirty = true
        schedulePreviewRebuild()
    }

    func discardRecovery() {
        guard let recovery = availableRecovery else { return }
        Task {
            do {
                try await store.discardRecovery(projectID: recovery.id)
                availableRecovery = nil
            } catch {
                present(error, messageKey: "error.recovery.discard")
            }
        }
    }

    func open(_ url: URL) async {
        do {
            let opened = try await LocalDiagnostics.shared.measure("project_open") {
                try await self.store.open(url)
            }
            install(opened, url: url)
            recentProjects.add(url)
            await updateMediaAvailability()
            scheduleAllWaveforms()
            schedulePreviewRebuild()
        } catch {
            present(error, messageKey: "error.project.open")
        }
    }

    func save() async -> Bool {
        guard let project else { return true }
        guard let projectURL else { return false }
        do {
            try await LocalDiagnostics.shared.measure("project_save") {
                try await self.store.save(project, to: projectURL)
            }
            try await store.discardRecovery(projectID: project.id)
            recentProjects.add(projectURL)
            isDirty = false
            return true
        } catch {
            present(error, messageKey: "error.project.save")
            return false
        }
    }

    func saveAs(_ url: URL) async -> Bool {
        projectURL = url
        let saved = await save()
        if !saved { projectURL = nil }
        return saved
    }

    func closeProject() async {
        autosaveTask?.cancel()
        previewTask?.cancel()
        waveformTasks.values.forEach { $0.cancel() }
        waveformTasks.removeAll()
        playback.stop()
        renderedComposition = nil
        await accessManager.releaseAll()
        project = nil
        projectURL = nil
        editor = nil
        selectedClipIDs = []
        selectedAssetID = nil
        waveforms = [:]
        mediaAvailability = [:]
        history.reset()
        isDirty = false
    }

    func importMedia(_ urls: [URL]) async {
        guard !urls.isEmpty, project != nil else { return }
        isImporting = true
        defer { isImporting = false }
        var imported: [MediaAsset] = []
        var failures: [String] = []
        for url in urls {
            do {
                try Task.checkCancellation()
                let reference = try await accessManager.makeReference(for: url)
                let inspection = try await inspector.inspect(url: url)
                imported.append(MediaAsset(
                    displayName: url.lastPathComponent,
                    kind: inspection.kind,
                    reference: reference,
                    metadata: inspection.metadata
                ))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !imported.isEmpty {
            performEdit { editor in
                for asset in imported { try editor.addAsset(asset) }
            }
            selectedAssetID = imported.first?.id
            for asset in imported { scheduleWaveform(for: asset) }
        }
        if !failures.isEmpty {
            presentedError = PresentedError(
                titleKey: "error.import.title",
                messageKey: "error.import.some_files",
                technicalDetail: failures.joined(separator: "\n")
            )
        }
    }

    func relink(assetID: UUID, to url: URL) async {
        guard let asset = project?.assets.first(where: { $0.id == assetID }) else { return }
        do {
            let reference = try await accessManager.makeReference(for: url)
            let inspection = try await inspector.inspect(url: url)
            var updated = asset
            updated.displayName = url.lastPathComponent
            updated.kind = inspection.kind
            updated.reference = reference
            updated.metadata = inspection.metadata
            performEdit { try $0.replaceAsset(updated) }
            mediaAvailability[assetID] = .available
            scheduleWaveform(for: updated)
        } catch {
            present(error, messageKey: "error.media.relink")
        }
    }

    func addAssetToTimeline(_ assetID: UUID, trackID: UUID? = nil, at proposedStart: RationalTime? = nil) {
        guard let project, let asset = project.assets.first(where: { $0.id == assetID }) else { return }
        let kind: ClipKind = switch asset.kind {
        case .video: .video
        case .audio: .audio
        case .image: .image
        }
        let compatible = kind.compatibleTrack
        guard let destination = trackID.flatMap({ id in
            project.timeline.tracks.first(where: { $0.id == id && $0.kind == compatible })
        }) ?? project.timeline.tracks.first(where: { $0.kind == compatible && !$0.isLocked }) else {
            present(EditingError.noCompatibleTrack, messageKey: "error.timeline.no_track")
            return
        }
        let appendTime = destination.clips.map(\.timelineEnd).max() ?? .zero
        let start = proposedStart ?? appendTime
        let duration = asset.metadata.duration ?? RationalTime(value: 5, timescale: 1)
        let clip = TimelineClip(
            name: asset.displayName,
            kind: kind,
            assetID: asset.id,
            timelineStart: start,
            duration: duration
        )
        performEdit { try $0.insert(clip, into: destination.id) }
        selectedClipIDs = [clip.id]
    }

    func addTextClip() {
        guard let project,
              let track = project.timeline.tracks.first(where: { $0.kind == .video && !$0.isLocked }) else {
            present(EditingError.noCompatibleTrack, messageKey: "error.timeline.no_track")
            return
        }
        let start = max(playback.currentTime, track.clips.map(\.timelineEnd).max() ?? .zero)
        let clip = TimelineClip(
            name: String(localized: "clip.text.default_name"),
            kind: .text,
            timelineStart: start,
            duration: RationalTime(value: 5, timescale: 1),
            textStyle: TextStyle(text: String(localized: "clip.text.default_content"))
        )
        performEdit { try $0.insert(clip, into: track.id) }
        selectedClipIDs = [clip.id]
    }

    func updateProjectSettings(name: String, preset: CanvasPreset, frameRate: ProjectFrameRate) {
        guard var updated = project, let before = project else { return }
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "project.untitled")
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.canvasPreset = preset
        updated.canvas = preset.resolution
        updated.frameRate = frameRate
        updated.exportPreferences.frameRate = frameRate
        updated.modifiedAt = Date()
        do {
            try ProjectValidator.validate(updated)
            editor = try ProjectEditor(project: updated)
            history.record(before)
            project = updated
            isDirty = true
            scheduleAutosave()
            schedulePreviewRebuild()
        } catch {
            present(error, messageKey: "error.project.settings")
        }
    }

    func updateExportPreferences(_ preferences: ExportPreferences) {
        guard var updated = project, let before = project else { return }
        updated.exportPreferences = preferences
        updated.modifiedAt = Date()
        do {
            try ProjectValidator.validate(updated)
            editor = try ProjectEditor(project: updated)
            history.record(before)
            project = updated
            isDirty = true
            scheduleAutosave()
        } catch {
            present(error, messageKey: "error.export.settings")
        }
    }

    func selectClip(_ id: UUID, extending: Bool) {
        if extending {
            if selectedClipIDs.contains(id) { selectedClipIDs.remove(id) } else { selectedClipIDs.insert(id) }
        } else {
            selectedClipIDs = [id]
        }
        selectedAssetID = nil
    }

    func moveClip(_ id: UUID, to start: RationalTime, trackID: UUID) {
        performEdit { try $0.moveClip(id, to: start, trackID: trackID) }
    }

    func trimClipStart(_ id: UUID, to start: RationalTime) {
        performEdit { try $0.trimStart(of: id, to: start) }
    }

    func trimClipEnd(_ id: UUID, to end: RationalTime) {
        performEdit { try $0.trimEnd(of: id, to: end) }
    }

    func updateClip(_ id: UUID, mutation: (inout TimelineClip) -> Void) {
        performEdit { try $0.updateClip(id, mutation: mutation) }
    }

    func splitSelection() {
        guard let id = selectedClipIDs.first else { return }
        do {
            var newID: UUID?
            performEdit { newID = try $0.splitClip(id, at: playback.currentTime) }
            if let newID { selectedClipIDs = [newID] }
        }
    }

    func deleteSelection() {
        guard !selectedClipIDs.isEmpty else { return }
        let ids = selectedClipIDs
        performEdit { try $0.deleteClips(ids) }
        selectedClipIDs = []
    }

    func duplicateSelection() {
        guard selectedClipIDs.count == 1, let id = selectedClipIDs.first else { return }
        var duplicate: UUID?
        performEdit { duplicate = try $0.duplicateClip(id) }
        if let duplicate { selectedClipIDs = [duplicate] }
    }

    func detachAudio() {
        guard selectedClipIDs.count == 1, let id = selectedClipIDs.first else { return }
        var detached: UUID?
        performEdit { detached = try $0.detachAudio(from: id) }
        if let detached { selectedClipIDs = [detached] }
    }

    func setTrackMuted(_ id: UUID, muted: Bool) {
        performEdit { try $0.setTrackMuted(id, muted: muted) }
    }

    func setTrackLocked(_ id: UUID, locked: Bool) {
        performEdit { try $0.setTrackLocked(id, locked: locked) }
    }

    func undo() {
        guard let project, let previous = history.undo(current: project) else { return }
        restoreHistoryState(previous)
    }

    func redo() {
        guard let project, let next = history.redo(current: project) else { return }
        restoreHistoryState(next)
    }

    func nudgePlayhead(frames: Int) {
        guard let project else { return }
        playback.seek(to: playback.currentTime + project.frameRate.value.frameDuration * Int64(frames))
    }

    func goToStart() { playback.seek(to: .zero) }
    func goToEnd() { playback.seek(to: project?.timeline.duration ?? .zero) }
    func zoomIn() { timelineZoom = min(timelineZoom * 1.25, 500) }
    func zoomOut() { timelineZoom = max(timelineZoom / 1.25, 12) }

    func snap(_ time: RationalTime, excluding id: UUID) -> RationalTime {
        guard let editor else { return max(time, .zero) }
        let threshold = RationalTime(seconds: 8 / timelineZoom, preferredTimescale: 6_000)
        return editor.snappedTime(
            proposed: max(time, .zero),
            playhead: playback.currentTime,
            excluding: id,
            threshold: threshold
        ).time
    }

    func thumbnail(for asset: MediaAsset, width: Int, height: Int) async -> CGImage? {
        do {
            let url = try await accessManager.resolve(asset.reference)
            return try await thumbnailGenerator.thumbnail(
                for: ThumbnailRequest(assetID: asset.id, time: .zero, pixelWidth: width, pixelHeight: height),
                url: url
            ).cgImage
        } catch {
            return nil
        }
    }

    func prepareExport() async -> RenderedComposition? {
        if let renderedComposition, renderedComposition.revision == project?.modifiedAt { return renderedComposition }
        guard let project else { return nil }
        do {
            let rendered = try await compositionBuilder.build(project: project)
            renderedComposition = rendered
            return rendered
        } catch {
            present(error, messageKey: "error.preview.build")
            return nil
        }
    }

    func export(
        rendered: RenderedComposition,
        plan: ExportPlan,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> ExportResult {
        try await exportService.export(
            rendered: rendered,
            plan: plan,
            destination: destination,
            progress: progress
        )
    }

    func cancelExport() async { await exportService.cancel() }

    func clearCache() async throws {
        await thumbnailGenerator.clearCache()
        await waveformGenerator.clearCache()
        await inspector.clearCache()
        try await cache.clear()
    }

    func cacheSize() async throws -> Int64 { try await cache.size() }
    func diagnosticEvents() async -> [DiagnosticEvent] { await LocalDiagnostics.shared.recentEvents() }

    private func install(_ project: CineleafProject, url: URL?) {
        do {
            editor = try ProjectEditor(project: project)
            self.project = project
            projectURL = url
            selectedClipIDs = []
            selectedAssetID = nil
            history.reset()
            isDirty = false
        } catch {
            present(error, messageKey: "error.project.invalid")
        }
    }

    private func performEdit(_ operation: (inout ProjectEditor) throws -> Void) {
        guard var editor, let before = project else { return }
        do {
            try operation(&editor)
            history.record(before)
            self.editor = editor
            project = editor.project
            isDirty = true
            scheduleAutosave()
            schedulePreviewRebuild()
        } catch {
            present(error, messageKey: "error.timeline.edit")
        }
    }

    private func restoreHistoryState(_ state: CineleafProject) {
        do {
            editor = try ProjectEditor(project: state)
            project = state
            isDirty = true
            selectedClipIDs = Set(selectedClipIDs.filter { id in
                state.timeline.tracks.flatMap(\.clips).contains { $0.id == id }
            })
            scheduleAutosave()
            schedulePreviewRebuild()
        } catch {
            present(error, messageKey: "error.history.restore")
        }
    }

    private func scheduleAutosave() {
        guard let project else { return }
        let url = projectURL
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                try await LocalDiagnostics.shared.measure("autosave") {
                    if let url {
                        try await self.store.save(project, to: url)
                    } else {
                        try await self.store.saveRecovery(project)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.present(error, messageKey: "error.autosave")
            }
        }
    }

    private func schedulePreviewRebuild() {
        guard let project, project.timeline.duration > .zero else {
            renderedComposition = nil
            playback.stop()
            return
        }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            self.isBuildingPreview = true
            defer { self.isBuildingPreview = false }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let rendered = try await self.compositionBuilder.build(project: project)
                guard !Task.isCancelled, self.project?.modifiedAt == rendered.revision else { return }
                self.renderedComposition = rendered
                self.playback.load(rendered)
            } catch is CancellationError {
                return
            } catch CompositionError.emptyTimeline {
                return
            } catch {
                self.present(error, messageKey: "error.preview.build")
            }
        }
    }

    private func scheduleAllWaveforms() {
        guard let project else { return }
        project.assets.forEach(scheduleWaveform)
    }

    private func scheduleWaveform(for asset: MediaAsset) {
        guard asset.kind == .audio || asset.metadata.hasAudio else { return }
        waveformTasks[asset.id]?.cancel()
        waveformTasks[asset.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await self.accessManager.resolve(asset.reference)
                let peaks = try await self.waveformGenerator.waveform(
                    for: WaveformRequest(assetID: asset.id, sampleCount: 600),
                    url: url
                )
                guard !Task.isCancelled else { return }
                self.waveforms[asset.id] = peaks
            } catch is CancellationError {
                return
            } catch {
                self.present(error, messageKey: "error.waveform.generate")
            }
        }
    }

    private func updateMediaAvailability() async {
        guard let project else { return }
        var values: [UUID: MediaAvailability] = [:]
        for asset in project.assets {
            do {
                _ = try await accessManager.resolve(asset.reference)
                values[asset.id] = .available
            } catch {
                values[asset.id] = .missing(lastKnownPath: asset.reference.lastKnownPath)
            }
        }
        mediaAvailability = values
    }

    private func present(_ error: Error, messageKey: String) {
        presentedError = PresentedError(
            titleKey: "error.title",
            messageKey: messageKey,
            technicalDetail: String(describing: error)
        )
    }
}
