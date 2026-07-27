import AppKit
import Foundation

@MainActor
final class RecentProjectsStore: ObservableObject {
    @Published private(set) var urls: [URL] = []
    private let defaultsKey = "CineleafRecentProjectPaths"
    private let limit = 10

    init() {
        reload()
    }

    func add(_ url: URL) {
        var paths = urls.map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: defaultsKey)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        reload()
    }

    func removeMissing() {
        UserDefaults.standard.set(
            urls.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.path),
            forKey: defaultsKey
        )
        reload()
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        NSDocumentController.shared.clearRecentDocuments(nil)
        reload()
    }

    private func reload() {
        urls = (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
