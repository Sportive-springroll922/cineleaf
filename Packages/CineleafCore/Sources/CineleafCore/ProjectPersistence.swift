import Foundation

public enum ProjectPersistenceError: Error, Equatable, Sendable {
    case invalidPackageExtension
    case packageIsNotDirectory
    case missingProjectFile
    case malformedDocument
    case unsupportedFutureVersion(Int)
    case migrationFailed(Int)
}

public struct ProjectCodec: Sendable {
    public init() {}

    public func encode(_ project: CineleafProject) throws -> Data {
        try ProjectValidator.validate(project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(project)
    }

    public func decode(_ data: Data) throws -> CineleafProject {
        let migrated = try migrate(data)
        let decoder = JSONDecoder()
        let project = try decoder.decode(CineleafProject.self, from: migrated)
        try ProjectValidator.validate(project)
        return project
    }

    public func migrate(_ data: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["formatVersion"] as? Int else {
            throw ProjectPersistenceError.malformedDocument
        }
        guard version <= CineleafProject.currentFormatVersion else {
            throw ProjectPersistenceError.unsupportedFutureVersion(version)
        }

        var workingVersion = version
        while workingVersion < CineleafProject.currentFormatVersion {
            switch workingVersion {
            case 0:
                object["formatVersion"] = 1
                workingVersion = 1
            case 1:
                migrateVersionOneToTwo(&object)
                object["formatVersion"] = 2
                workingVersion = 2
            default:
                throw ProjectPersistenceError.migrationFailed(workingVersion)
            }
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private func migrateVersionOneToTwo(_ object: inout [String: Any]) {
        guard var timeline = object["timeline"] as? [String: Any],
              var tracks = timeline["tracks"] as? [[String: Any]] else { return }
        timeline["markers"] = timeline["markers"] ?? []
        for trackIndex in tracks.indices {
            guard var clips = tracks[trackIndex]["clips"] as? [[String: Any]] else { continue }
            for clipIndex in clips.indices {
                clips[clipIndex]["playbackRate"] = clips[clipIndex]["playbackRate"] ?? 1.0
                clips[clipIndex]["isReversed"] = clips[clipIndex]["isReversed"] ?? false
                clips[clipIndex]["role"] = clips[clipIndex]["role"] ?? ClipRole.standard.rawValue
                clips[clipIndex]["colorAdjustments"] = clips[clipIndex]["colorAdjustments"] ?? [
                    "exposure": 0.0, "contrast": 1.0, "saturation": 1.0, "temperature": 0.0,
                    "tint": 0.0, "highlights": 0.0, "shadows": 0.0, "sharpen": 0.0, "vignette": 0.0
                ]
                clips[clipIndex]["effects"] = clips[clipIndex]["effects"] ?? []
                clips[clipIndex]["keyframes"] = clips[clipIndex]["keyframes"] ?? [
                    "positionX": [], "positionY": [], "scale": [], "rotationDegrees": [],
                    "opacity": [], "volume": []
                ]
            }
            tracks[trackIndex]["clips"] = clips
        }
        timeline["tracks"] = tracks
        object["timeline"] = timeline
    }
}

public actor ProjectPackageStore {
    public static let projectFilename = "project.json"
    private let fileManager: FileManager
    private let codec: ProjectCodec
    private let recoveryDirectory: URL

    public init(
        fileManager: FileManager = .default,
        codec: ProjectCodec = ProjectCodec(),
        recoveryDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.codec = codec
        if let recoveryDirectory {
            self.recoveryDirectory = recoveryDirectory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.recoveryDirectory = applicationSupport
                .appendingPathComponent("Cineleaf", isDirectory: true)
                .appendingPathComponent("Recovery", isDirectory: true)
        }
    }

    public func save(_ project: CineleafProject, to packageURL: URL) throws {
        guard packageURL.pathExtension.lowercased() == "cineleaf" else {
            throw ProjectPersistenceError.invalidPackageExtension
        }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw ProjectPersistenceError.packageIsNotDirectory }
        } else {
            try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        }
        let data = try codec.encode(project)
        try data.write(to: packageURL.appendingPathComponent(Self.projectFilename), options: .atomic)
    }

    public func open(_ packageURL: URL) throws -> CineleafProject {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectPersistenceError.packageIsNotDirectory
        }
        let projectURL = packageURL.appendingPathComponent(Self.projectFilename)
        guard fileManager.fileExists(atPath: projectURL.path) else {
            throw ProjectPersistenceError.missingProjectFile
        }
        return try codec.decode(Data(contentsOf: projectURL, options: .mappedIfSafe))
    }

    public func saveRecovery(_ project: CineleafProject) throws {
        try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let url = recoveryURL(for: project.id)
        try codec.encode(project).write(to: url, options: .atomic)
    }

    public func availableRecoveries() throws -> [CineleafProject] {
        guard fileManager.fileExists(atPath: recoveryDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? codec.decode(Data(contentsOf: $0, options: .mappedIfSafe)) }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func discardRecovery(projectID: UUID) throws {
        let url = recoveryURL(for: projectID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func recoveryURL(for projectID: UUID) -> URL {
        recoveryDirectory.appendingPathComponent(projectID.uuidString).appendingPathExtension("json")
    }
}

public enum FilenameSanitizer {
    public static func sanitize(_ input: String, fallback: String = "Cineleaf Export") -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let components = input.components(separatedBy: forbidden)
        let collapsed = components.joined(separator: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return collapsed.isEmpty ? fallback : String(collapsed.prefix(120))
    }
}
