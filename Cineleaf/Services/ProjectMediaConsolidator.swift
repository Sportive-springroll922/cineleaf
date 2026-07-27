import CineleafCore
import Foundation

enum ProjectMediaConsolidationError: Error {
    case projectMustBeSaved
    case insufficientSpace
}

actor ProjectMediaConsolidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func copy(asset: MediaAsset, from source: URL, into packageURL: URL) throws -> MediaReference {
        try Task.checkCancellation()
        let directory = packageURL.appendingPathComponent("Media", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = FilenameSanitizer.sanitize(asset.displayName, fallback: "media")
        let relativePath = "Media/\(asset.id.uuidString)-\(safeName)"
        let destination = packageURL.appendingPathComponent(relativePath)
        if !fileManager.fileExists(atPath: destination.path) {
            let sourceSize = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let capacity = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            if let capacity, capacity < sourceSize + 64 * 1_024 * 1_024 {
                throw ProjectMediaConsolidationError.insufficientSpace
            }
            let temporary = directory.appendingPathComponent(".\(UUID().uuidString).partial")
            defer { try? fileManager.removeItem(at: temporary) }
            try fileManager.copyItem(at: source, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        }
        let values = try? destination.resourceValues(forKeys: [.contentModificationDateKey])
        return MediaReference(
            lastKnownPath: destination.path,
            projectRelativePath: relativePath,
            sourceModificationDate: values?.contentModificationDate
        )
    }
}
