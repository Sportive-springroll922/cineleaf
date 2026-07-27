import CineleafCore
import SwiftUI

struct ErrorSheet: View {
    let error: PresentedError
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(LocalizedStringKey(error.titleKey))
                    .font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(LocalizedStringKey(error.messageKey))
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("error.technical_details") {
                Text(error.technicalDetail)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            HStack {
                Spacer()
                Button("action.ok") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct RecoverySheet: View {
    let project: CineleafProject
    @EnvironmentObject private var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("recovery.title", systemImage: "arrow.counterclockwise.circle.fill")
                .font(.title2.weight(.semibold))
            Text("recovery.message")
            Text(project.name)
                .font(.headline)
            HStack {
                Button("recovery.discard", role: .destructive) { state.discardRecovery() }
                Spacer()
                Button("recovery.restore") { state.recover(project) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }
}
