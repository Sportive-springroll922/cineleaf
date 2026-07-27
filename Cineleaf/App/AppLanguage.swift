import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case spanish

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .spanish: Locale(identifier: "es-ES")
        }
    }

    var localizationKey: String {
        switch self {
        case .system: "settings.language.system"
        case .english: "settings.language.english"
        case .spanish: "settings.language.spanish"
        }
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    @Published var selection: AppLanguage {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "CineleafPreferredLanguage"

    init() {
        let value = UserDefaults.standard.string(forKey: Self.defaultsKey)
        selection = AppLanguage(rawValue: value ?? "") ?? .system
    }
}
