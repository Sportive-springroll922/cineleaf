import SwiftUI

@main
@MainActor
struct CineleafApp: App {
    @StateObject private var editorState = EditorState()
    @StateObject private var languageSettings = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(editorState)
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.selection.locale)
                .onOpenURL { url in Task { await editorState.open(url) } }
                .frame(minWidth: 1_020, minHeight: 700)
        }
        .commands {
            CineleafCommands(state: editorState)
        }

        Settings {
            SettingsView()
                .environmentObject(editorState)
                .environmentObject(languageSettings)
                .environment(\.locale, languageSettings.selection.locale)
        }

        Window("about.window.title", id: "about") {
            AboutView()
                .environment(\.locale, languageSettings.selection.locale)
        }
        .windowResizability(.contentSize)
    }
}
