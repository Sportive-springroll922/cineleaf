import AVKit
import CineleafCore
import SwiftUI

struct PreviewView: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if state.renderedComposition != nil {
                    VideoPlayer(player: state.playback.player)
                        .aspectRatio(canvasAspectRatio, contentMode: .fit)
                } else {
                    ContentUnavailableView {
                        Label("preview.empty.title", systemImage: "play.rectangle")
                    } description: {
                        Text("preview.empty.message")
                    }
                    .foregroundStyle(.white.opacity(0.82))
                }
                if state.isBuildingPreview {
                    ProgressView()
                        .controlSize(.small)
                        .padding(9)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("preview.accessibility")

            PlaybackControls(playback: state.playback)
        }
    }

    private var canvasAspectRatio: CGFloat {
        guard let canvas = state.project?.canvas, canvas.height > 0 else { return 16 / 9 }
        return CGFloat(canvas.width) / CGFloat(canvas.height)
    }
}

private struct PlaybackControls: View {
    @Environment(\.locale) private var locale
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: 12) {
            Button { playback.togglePlayback() } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help("playback.toggle.help")
            Slider(
                value: Binding(
                    get: { playback.currentTime.seconds },
                    set: { playback.seek(to: RationalTime(seconds: $0, preferredTimescale: 6_000)) }
                ),
                in: 0...max(playback.duration.seconds, 0.001)
            )
            .accessibilityLabel("timeline.playhead")
            Text(DurationText.string(playback.currentTime, locale: locale))
                .monospacedDigit()
            Text("/")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(DurationText.string(playback.duration, locale: locale))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
    }
}
