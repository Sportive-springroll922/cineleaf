import AVFoundation
import CineleafCore
import CoreGraphics
import CoreVideo
import Foundation

enum ReverseMediaError: Error {
    case missingVideoTrack
    case unsupportedAudioFormat
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case cannotCreateContext
    case writerFailed
}

private final class ReverseWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter
    init(_ writer: AVAssetWriter) { self.writer = writer }
}

actor ReverseMediaService {
    private let store: MediaDerivativeStore

    init(store: MediaDerivativeStore = .shared) {
        self.store = store
    }

    func video(
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        frameRate: RationalRate
    ) async throws -> URL {
        let key = try cacheKey(
            prefix: "reverse-video",
            url: url,
            sourceStart: sourceStart,
            sourceDuration: sourceDuration,
            rate: frameRate.framesPerSecond
        )
        if let cached = try await store.cachedURL(for: key, extension: "mov") { return cached }
        let temporary = try await store.temporaryURL(extension: "mov")
        do {
            try await renderVideo(
                sourceURL: url,
                destinationURL: temporary,
                sourceStart: sourceStart,
                sourceDuration: sourceDuration,
                frameRate: frameRate
            )
            return try await store.commit(temporary, for: key, extension: "mov")
        } catch {
            await store.discard(temporary)
            throw error
        }
    }

    func audio(
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime
    ) async throws -> URL {
        let key = try cacheKey(
            prefix: "reverse-audio",
            url: url,
            sourceStart: sourceStart,
            sourceDuration: sourceDuration,
            rate: 0
        )
        if let cached = try await store.cachedURL(for: key, extension: "caf") { return cached }
        let temporary = try await store.temporaryURL(extension: "caf")
        do {
            try renderAudio(
                sourceURL: url,
                destinationURL: temporary,
                sourceStart: sourceStart,
                sourceDuration: sourceDuration
            )
            return try await store.commit(temporary, for: key, extension: "caf")
        } catch {
            await store.discard(temporary)
            throw error
        }
    }

    private func renderVideo(
        sourceURL: URL,
        destinationURL: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        frameRate: RationalRate
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReverseMediaError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let width = max(Int(abs(displayRect.width).rounded()), 2)
        let height = max(Int(abs(displayRect.height).rounded()), 2)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(width * height * 6, 1_000_000),
                AVVideoMaxKeyFrameIntervalKey: max(Int(frameRate.framesPerSecond.rounded()), 1)
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw ReverseMediaError.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ReverseMediaError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let fps = frameRate.framesPerSecond
        let frameCount = max(Int((sourceDuration.seconds * fps).rounded(.up)), 1)
        for frameIndex in 0..<frameCount {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(2))
            }
            let reversedOffset = max(sourceDuration.seconds - (Double(frameIndex) + 0.5) / fps, 0)
            let sourceTime = CMTime(
                seconds: sourceStart.seconds + reversedOffset,
                preferredTimescale: 60_000
            )
            let image = try await generator.image(at: sourceTime).image
            guard let pool = adaptor.pixelBufferPool else { throw ReverseMediaError.cannotCreatePixelBuffer }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else { throw ReverseMediaError.cannotCreatePixelBuffer }
            try draw(image, into: buffer, width: width, height: height)
            guard adaptor.append(
                buffer,
                withPresentationTime: CMTime(
                    value: Int64(frameIndex) * Int64(frameRate.denominator),
                    timescale: frameRate.numerator
                )
            ) else {
                throw writer.error ?? ReverseMediaError.writerFailed
            }
        }
        input.markAsFinished()
        let box = ReverseWriterBox(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.writer.finishWriting {
                if box.writer.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: box.writer.error ?? ReverseMediaError.writerFailed) }
            }
        }
    }

    private func renderAudio(
        sourceURL: URL,
        destinationURL: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime
    ) throws {
        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        guard format.commonFormat == .pcmFormatFloat32 else {
            throw ReverseMediaError.unsupportedAudioFormat
        }
        let channels = Int(format.channelCount)
        let destination = try AVAudioFile(forWriting: destinationURL, settings: format.settings)
        let startFrame = AVAudioFramePosition((sourceStart.seconds * format.sampleRate).rounded())
        var remaining = min(
            AVAudioFramePosition((sourceDuration.seconds * format.sampleRate).rounded()),
            max(source.length - startFrame, 0)
        )
        let capacity: AVAudioFrameCount = 32_768
        while remaining > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(remaining, AVAudioFramePosition(capacity)))
            source.framePosition = startFrame + remaining - AVAudioFramePosition(count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                throw ReverseMediaError.unsupportedAudioFormat
            }
            try source.read(into: buffer, frameCount: count)
            if let data = buffer.floatChannelData {
                for channel in 0..<channels {
                    for left in 0..<(Int(buffer.frameLength) / 2) {
                        let right = Int(buffer.frameLength) - left - 1
                        let value = data[channel][left]
                        data[channel][left] = data[channel][right]
                        data[channel][right] = value
                    }
                }
            }
            try destination.write(from: buffer)
            remaining -= AVAudioFramePosition(count)
        }
    }

    private func draw(_ image: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else { throw ReverseMediaError.cannotCreateContext }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }

    private func cacheKey(
        prefix: String,
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        rate: Double
    ) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            prefix, url.path, "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)",
            "\(values.fileSize ?? 0)", "\(sourceStart.value)/\(sourceStart.timescale)",
            "\(sourceDuration.value)/\(sourceDuration.timescale)", "\(rate)"
        ].joined(separator: "|")
    }
}
