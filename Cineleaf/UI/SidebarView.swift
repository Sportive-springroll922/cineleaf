import AppKit
import CineleafCore
import SwiftUI
import UniformTypeIdentifiers

private enum SidebarSection: String, CaseIterable, Identifiable {
    case media
    case text
    var id: String { rawValue }
    var key: LocalizedStringKey { self == .media ? "sidebar.media" : "sidebar.text" }
}

struct SidebarView: View {
    @EnvironmentObject private var state: EditorState
    @State private var section = SidebarSection.media
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("sidebar.section", selection: $section) {
                ForEach(SidebarSection.allCases) { section in
                    Text(section.key).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()
            switch section {
            case .media:
                mediaLibrary
            case .text:
                textLibrary
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var mediaLibrary: some View {
        if let assets = state.project?.assets, !assets.isEmpty {
            List(assets, selection: $state.selectedAssetID) { asset in
                MediaAssetRow(asset: asset)
                    .tag(asset.id)
                    .draggable(asset.id.uuidString)
                    .contextMenu {
                        Button("timeline.add_selected") { state.addAssetToTimeline(asset.id) }
                        if case .missing = state.mediaAvailability[asset.id] {
                            Button("media.relink") { relink(asset) }
                        }
                    }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button { importPanel() } label: {
                        Label("media.import", systemImage: "plus")
                    }
                    Spacer()
                    Button("timeline.add_selected") {
                        if let id = state.selectedAssetID { state.addAssetToTimeline(id) }
                    }
                    .disabled(state.selectedAssetID == nil)
                }
                .padding(8)
                .background(.bar)
            }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await state.importMedia(urls) }
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .padding(6)
                }
            }
        } else {
            ContentUnavailableView {
                Label("media.empty.title", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("media.empty.message")
            } actions: {
                Button("media.import") { importPanel() }
                    .buttonStyle(.borderedProminent)
            }
            .dropDestination(for: URL.self) { urls, _ in
                Task { await state.importMedia(urls) }
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }
        }
    }

    private var textLibrary: some View {
        ContentUnavailableView {
            Label("text.add.title", systemImage: "textformat")
        } description: {
            Text("text.add.message")
        } actions: {
            Button("text.add.action") { state.addTextClip() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func importPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "media.import")
        panel.allowedContentTypes = [.movie, .audio, .image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        Task { await state.importMedia(panel.urls) }
    }

    private func relink(_ asset: MediaAsset) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "media.relink")
        panel.allowedContentTypes = [.movie, .audio, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await state.relink(assetID: asset.id, to: url) }
    }
}

private struct MediaAssetRow: View {
    @EnvironmentObject private var state: EditorState
    let asset: MediaAsset
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: asset.kind.symbolName)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 44)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.displayName)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(asset.kind.localizationKey)
                    if let duration = asset.metadata.duration {
                        Text("•")
                        Text(DurationText.string(duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let resolution = asset.metadata.resolution {
                    Text("\(resolution.width) × \(resolution.height) · \(asset.metadata.fileType.uppercased())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if case .missing = state.mediaAvailability[asset.id] {
                    Label("media.missing", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 3)
        .task(id: asset.reference.sourceModificationDate) {
            thumbnail = await state.thumbnail(for: asset, width: 144, height: 88)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("media.item.accessibility \(asset.displayName)"))
    }
}

private extension MediaKind {
    var symbolName: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        }
    }

    var localizationKey: LocalizedStringKey {
        switch self {
        case .video: "media.kind.video"
        case .audio: "media.kind.audio"
        case .image: "media.kind.image"
        }
    }
}
