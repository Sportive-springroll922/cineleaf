import Foundation

actor BoundedCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry: Sendable {
        var value: Value
        var access: UInt64
    }

    private var entries: [Key: Entry] = [:]
    private var counter: UInt64 = 0
    private let limit: Int

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        counter &+= 1
        entry.access = counter
        entries[key] = entry
        return entry.value
    }

    func insert(_ value: Value, for key: Key) {
        counter &+= 1
        entries[key] = Entry(value: value, access: counter)
        guard entries.count > limit,
              let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { return }
        entries.removeValue(forKey: oldest)
    }

    func removeAll() { entries.removeAll(keepingCapacity: false) }
    var count: Int { entries.count }
}

actor DerivedDataCache {
    static let shared = DerivedDataCache()
    private let fileManager: FileManager
    private let directory: URL
    private let maximumBytes: Int64

    init(fileManager: FileManager = .default, maximumBytes: Int64 = 512 * 1_024 * 1_024) {
        self.fileManager = fileManager
        self.maximumBytes = maximumBytes
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = base.appendingPathComponent("org.cineleaf.Cineleaf", isDirectory: true)
            .appendingPathComponent("Derived", isDirectory: true)
    }

    func data(for key: String) throws -> Data? {
        let url = cacheURL(key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func store(_ data: Data, for key: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: cacheURL(key), options: .atomic)
        try evictIfNeeded()
    }

    func size() throws -> Int64 {
        try entries().reduce(0) { partial, url in
            partial + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for url in try entries() { try fileManager.removeItem(at: url) }
    }

    private func evictIfNeeded() throws {
        var candidates = try entries().map { url -> (URL, Int64, Date) in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
        var total = candidates.reduce(Int64(0)) { $0 + $1.1 }
        for candidate in candidates.sorted(by: { $0.2 < $1.2 }) where total > maximumBytes {
            try fileManager.removeItem(at: candidate.0)
            total -= candidate.1
        }
    }

    private func entries() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    }

    private func cacheURL(_ key: String) -> URL {
        let safe = key.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return directory.appendingPathComponent(String(safe.prefix(180))).appendingPathExtension("cache")
    }
}
