import CryptoKit
import Foundation

actor MediaDerivativeStore {
    static let shared = MediaDerivativeStore()

    private let fileManager: FileManager
    private let directory: URL
    private let maximumBytes: Int64

    init(fileManager: FileManager = .default, maximumBytes: Int64 = 2 * 1_024 * 1_024 * 1_024) {
        self.fileManager = fileManager
        self.maximumBytes = maximumBytes
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("org.cineleaf.Cineleaf", isDirectory: true)
            .appendingPathComponent("MediaDerivatives", isDirectory: true)
    }

    func cachedURL(for key: String, extension pathExtension: String) throws -> URL? {
        let url = destinationURL(for: key, extension: pathExtension)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    func temporaryURL(extension pathExtension: String) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pending-\(UUID().uuidString)").appendingPathExtension(pathExtension)
    }

    func commit(_ temporaryURL: URL, for key: String, extension pathExtension: String) throws -> URL {
        let destination = destinationURL(for: key, extension: pathExtension)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        try evictIfNeeded(excluding: destination)
        return destination
    }

    func discard(_ temporaryURL: URL) {
        if fileManager.fileExists(atPath: temporaryURL.path) { try? fileManager.removeItem(at: temporaryURL) }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func destinationURL(for key: String, extension pathExtension: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension(pathExtension)
    }

    private func evictIfNeeded(excluding protectedURL: URL) throws {
        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { !$0.lastPathComponent.hasPrefix("pending-") }
        let values = candidates.map { url -> (url: URL, size: Int64, date: Date) in
            let resource = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, Int64(resource?.fileSize ?? 0), resource?.contentModificationDate ?? .distantPast)
        }
        var total = values.reduce(Int64(0)) { $0 + $1.size }
        for candidate in values.sorted(by: { $0.date < $1.date })
            where total > maximumBytes && candidate.url != protectedURL {
            try fileManager.removeItem(at: candidate.url)
            total -= candidate.size
        }
    }
}
