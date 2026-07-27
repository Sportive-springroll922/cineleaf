import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CineleafCore

enum MediaInspectionError: Error {
    case unsupportedFile
    case unreadableFile
    case invalidDuration
}

struct MediaInspection: Sendable {
    var kind: MediaKind
    var metadata: MediaMetadata
}

actor AVMediaInspector: MediaInspecting {
    typealias Inspection = MediaInspection
    private let cache = BoundedCache<String, MediaInspection>(limit: 256)

    func inspect(url: URL) async throws -> MediaInspection {
        let key = try cacheKey(url)
        if let cached = await cache.value(for: key) { return cached }
        let result = try await LocalDiagnostics.shared.measure("media_import") {
            try Task.checkCancellation()
            return try await Self.read(url: url)
        }
        await cache.insert(result, for: key)
        return result
    }

    func clearCache() async { await cache.removeAll() }

    private static func read(url: URL) async throws -> MediaInspection {
        let type = UTType(filenameExtension: url.pathExtension)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(values.fileSize ?? 0)
        if type?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else {
                throw MediaInspectionError.unreadableFile
            }
            return MediaInspection(
                kind: .image,
                metadata: MediaMetadata(
                    resolution: Resolution(width: width, height: height),
                    fileType: type?.preferredFilenameExtension ?? url.pathExtension.lowercased(),
                    hasAudio: false,
                    fileSize: fileSize
                )
            )
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else { throw MediaInspectionError.unsupportedFile }
        guard duration.isNumeric, duration > .zero else { throw MediaInspectionError.invalidDuration }

        let kind: MediaKind = videoTracks.isEmpty ? .audio : .video
        var resolution: Resolution?
        var frameRate: RationalRate?
        if let track = videoTracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
            resolution = Resolution(
                width: Int(abs(transformed.width).rounded()),
                height: Int(abs(transformed.height).rounded())
            )
            frameRate = rationalRate(from: try await track.load(.nominalFrameRate))
        }

        return MediaInspection(
            kind: kind,
            metadata: MediaMetadata(
                duration: RationalTime(duration),
                resolution: resolution,
                frameRate: frameRate,
                fileType: type?.preferredFilenameExtension ?? url.pathExtension.lowercased(),
                hasAudio: !audioTracks.isEmpty,
                fileSize: fileSize
            )
        )
    }

    private static func rationalRate(from nominalRate: Float) -> RationalRate? {
        guard nominalRate > 0, nominalRate.isFinite else { return nil }
        let value = Double(nominalRate)
        let commonRates: [(Double, RationalRate)] = [
            (23.976, RationalRate(numerator: 24_000, denominator: 1_001)),
            (29.97, RationalRate(numerator: 30_000, denominator: 1_001)),
            (59.94, RationalRate(numerator: 60_000, denominator: 1_001))
        ]
        if let match = commonRates.first(where: { abs($0.0 - value) < 0.02 }) { return match.1 }
        return RationalRate(numerator: Int32(value.rounded()))
    }

    private func cacheKey(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(url.path)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)"
    }
}
