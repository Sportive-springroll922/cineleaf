import CineleafCore
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        TimelineContent(playback: state.playback)
    }
}

private struct TimelineContent: View {
    @EnvironmentObject private var state: EditorState
    @Environment(\.locale) private var locale
    @ObservedObject var playback: PlaybackController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("timeline.title")
                    .font(.headline)
                let clipCount = state.project?.timeline.tracks.flatMap(\.clips).count ?? 0
                Text(String.localizedStringWithFormat(String(localized: "timeline.clip_count"), Int64(clipCount)))
                    .foregroundStyle(.secondary)
                Text(DurationText.string(playback.currentTime, locale: locale))
                    .monospacedDigit()
                Text("/")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(DurationText.string(state.project?.timeline.duration ?? .zero, locale: locale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button { state.splitSelection() } label: {
                    Label("timeline.split", systemImage: "scissors")
                }
                .disabled(state.selectedClipIDs.count != 1)
                Button { state.deleteSelection() } label: {
                    Label("timeline.delete", systemImage: "trash")
                }
                .disabled(state.selectedClipIDs.isEmpty)
                Button { state.rippleDeleteSelection() } label: {
                    Label("timeline.ripple_delete", systemImage: "delete.backward")
                }
                .disabled(state.selectedClipIDs.isEmpty)
                Button { state.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("timeline.zoom_out")
                Slider(value: $state.timelineZoom, in: 12...500)
                    .frame(width: 110)
                    .accessibilityLabel("timeline.zoom")
                Button { state.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("timeline.zoom_in")
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(.bar)

            if let project = state.project {
                TimelineScrollView(
                    project: project,
                    selectedClipIDs: state.selectedClipIDs,
                    pixelsPerSecond: state.timelineZoom,
                    playhead: playback.currentTime,
                    waveforms: state.waveforms,
                    locale: locale,
                    onSelect: state.selectClip,
                    onMove: state.moveClip,
                    onTrimStart: state.trimClipStart,
                    onTrimEnd: state.trimClipEnd,
                    onSeek: playback.seek,
                    onSnap: state.snap,
                    onDropAsset: state.addAssetToTimeline,
                    onMuteTrack: state.setTrackMuted,
                    onLockTrack: state.setTrackLocked
                )
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
