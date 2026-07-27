import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FreezeFrameError: Error {
    case cannotCreateImage
    case cannotWriteImage
}

actor FreezeFrameService {
    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directory = base.appendingPathComponent("Cineleaf", isDirectory: true)
                .appendingPathComponent("Freeze Frames", isDirectory: true)
        }
    }

    func create(url: URL, sourceTime: CMTime) async throws -> URL {
        try Task.checkCancellation()
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let image = try await generator.image(at: sourceTime).image
        try Task.checkCancellation()

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw FreezeFrameError.cannotCreateImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FreezeFrameError.cannotWriteImage }
        return output
    }
}
