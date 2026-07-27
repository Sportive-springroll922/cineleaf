import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CineleafCore

struct ThumbnailImage: @unchecked Sendable {
    let cgImage: CGImage
}

enum ThumbnailError: Error {
    case unsupportedFile
    case generationFailed
}

actor AVThumbnailGenerator: ThumbnailGenerating {
    typealias Image = ThumbnailImage
    private let cache = BoundedCache<String, ThumbnailImage>(limit: 256)
    private let diskCache = DerivedDataCache.shared
    private var activeGenerators: [UUID: AVAssetImageGenerator] = [:]

    func thumbnail(for request: ThumbnailRequest, url: URL) async throws -> ThumbnailImage {
        let key = try cacheKey(request: request, url: url)
        if let cached = await cache.value(for: key) { return cached }
        if let data = try? await diskCache.data(for: "thumbnail|\(key)"),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let diskImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let image = ThumbnailImage(cgImage: diskImage)
            await cache.insert(image, for: key)
            return image
        }
        let image = try await LocalDiagnostics.shared.measure("thumbnail_generation") {
            try Task.checkCancellation()
            return try await self.generate(request: request, url: url)
        }
        await cache.insert(image, for: key)
        if let data = pngData(image.cgImage) {
            try? await diskCache.store(data, for: "thumbnail|\(key)")
        }
        return image
    }

    func cancel(assetID: UUID) {
        activeGenerators[assetID]?.cancelAllCGImageGeneration()
        activeGenerators.removeValue(forKey: assetID)
    }

    func clearCache() async { await cache.removeAll() }

    private func generate(request: ThumbnailRequest, url: URL) async throws -> ThumbnailImage {
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(request.pixelWidth, request.pixelHeight)
                  ] as CFDictionary) else {
                throw ThumbnailError.generationFailed
            }
            return ThumbnailImage(cgImage: image)
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: request.pixelWidth, height: request.pixelHeight)
        generator.requestedTimeToleranceBefore = request.time == .zero ? .zero : .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        activeGenerators[request.assetID]?.cancelAllCGImageGeneration()
        activeGenerators[request.assetID] = generator
        defer { activeGenerators.removeValue(forKey: request.assetID) }
        let result = try await generator.image(at: request.time.cmTime)
        try Task.checkCancellation()
        return ThumbnailImage(cgImage: result.image)
    }

    private func cacheKey(request: ThumbnailRequest, url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            request.assetID.uuidString,
            "\(request.time.value)-\(request.time.timescale)",
            "\(request.pixelWidth)x\(request.pixelHeight)",
            "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)",
            "\(values.fileSize ?? 0)"
        ].joined(separator: "|")
    }

    private func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
