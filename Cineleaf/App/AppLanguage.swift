import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case spanish

    var id: String { rawValue }

    var overrideLocale: Locale? {
        switch self {
        case .system: nil
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

extension View {
    @ViewBuilder
    func cineleafLocale(_ language: AppLanguage) -> some View {
        if let locale = language.overrideLocale {
            environment(\.locale, locale)
        } else {
            self
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
