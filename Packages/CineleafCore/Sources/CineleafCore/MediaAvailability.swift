import Foundation

public enum MediaAvailability: Equatable, Sendable {
    case available
    case missing(lastKnownPath: String)
}

public enum MissingMediaDetector {
    public static func statuses(
        in project: CineleafProject,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [UUID: MediaAvailability] {
        Dictionary(uniqueKeysWithValues: project.assets.map { asset in
            let path = asset.reference.lastKnownPath
            return (asset.id, fileExists(path) ? .available : .missing(lastKnownPath: path))
        })
    }
}

