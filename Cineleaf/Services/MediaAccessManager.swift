import Foundation
import CineleafCore

enum MediaAccessError: Error {
    case missingFile(String)
    case invalidBookmark
    case permissionDenied(String)
}

actor MediaAccessManager {
    private var accessedURLs: [URL: Int] = [:]

    func makeReference(for url: URL) throws -> MediaReference {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaAccessError.missingFile(url.path)
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: [.contentModificationDateKey],
            relativeTo: nil
        )
        return MediaReference(
            lastKnownPath: url.path,
            securityScopedBookmark: bookmark,
            sourceModificationDate: values?.contentModificationDate
        )
    }

    func resolve(_ reference: MediaReference) throws -> URL {
        let resolved: URL
        if let bookmark = reference.securityScopedBookmark {
            var stale = false
            do {
                resolved = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
            } catch {
                throw MediaAccessError.invalidBookmark
            }
        } else {
            resolved = URL(fileURLWithPath: reference.lastKnownPath)
        }

        guard FileManager.default.fileExists(atPath: resolved.path) else {
            throw MediaAccessError.missingFile(reference.lastKnownPath)
        }
        if accessedURLs[resolved] == nil {
            guard resolved.startAccessingSecurityScopedResource() || reference.securityScopedBookmark == nil else {
                throw MediaAccessError.permissionDenied(reference.lastKnownPath)
            }
            accessedURLs[resolved] = 1
        }
        return resolved
    }

    func release(_ url: URL) {
        guard accessedURLs[url] != nil else { return }
        url.stopAccessingSecurityScopedResource()
        accessedURLs.removeValue(forKey: url)
    }

    func releaseAll() {
        for url in accessedURLs.keys { url.stopAccessingSecurityScopedResource() }
        accessedURLs.removeAll()
    }
}
