import CineleafCore
import SwiftUI

struct SilenceRemovalProposal: Identifiable {
    let id = UUID()
    let clipID: UUID
    let ranges: [RationalTimeRange]

    var totalDuration: Double { ranges.reduce(0) { $0 + $1.duration.seconds } }
}

struct SilenceRemovalSheet: View {
    @EnvironmentObject private var state: EditorState
    let proposal: SilenceRemovalProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("silence.review.title")
                .font(.title2.bold())
            Text(String.localizedStringWithFormat(
                String(localized: "silence.review.summary"),
                Int64(proposal.ranges.count),
                proposal.totalDuration
            ))
            List(proposal.ranges.indices, id: \.self) { index in
                let range = proposal.ranges[index]
                Button {
                    state.playback.seek(to: range.start)
                } label: {
                    HStack {
                        Text(DurationText.string(range.start)).monospacedDigit()
                        Image(systemName: "arrow.right")
                        Text(DurationText.string(range.end)).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 180)
            Text("silence.review.warning")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("action.cancel") { state.pendingSilenceRemoval = nil }
                Spacer()
                Button("silence.apply", role: .destructive) { state.applySilenceRemoval() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
