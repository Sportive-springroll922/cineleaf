import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: EditorState

    var body: some View {
        Group {
            if state.project == nil {
                WelcomeView()
            } else {
                EditorView()
            }
        }
        .sheet(isPresented: $state.isNewProjectSheetPresented) {
            NewProjectSheet()
        }
        .sheet(isPresented: $state.isProjectSettingsPresented) {
            ProjectSettingsSheet()
        }
        .sheet(isPresented: $state.isExportSheetPresented) {
            ExportSheet()
        }
        .sheet(item: $state.presentedError) { error in
            ErrorSheet(error: error)
        }
        .sheet(item: $state.availableRecovery) { recovery in
            RecoverySheet(project: recovery)
        }
        .sheet(item: $state.pendingSilenceRemoval) { proposal in
            SilenceRemovalSheet(proposal: proposal)
        }
    }
}
