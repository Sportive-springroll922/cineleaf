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
                .cineleafLocale(languageSettings.selection)
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
                .cineleafLocale(languageSettings.selection)
        }

        Window("about.window.title", id: "about") {
            AboutView()
                .cineleafLocale(languageSettings.selection)
        }
        .windowResizability(.contentSize)
    }
}
