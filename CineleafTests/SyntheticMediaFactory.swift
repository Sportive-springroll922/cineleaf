import AVFAudio
import AVFoundation
import CoreVideo
import Foundation
import XCTest

enum SyntheticMediaError: Error {
    case cannotCreateWriter
    case writerFailed
    case pixelBufferFailed
    case audioBufferFailed
}

private final class AssetWriterBox: @unchecked Sendable {
    let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }
}

enum SyntheticMediaFactory {
    static func makeVideo(at url: URL, seconds: Int = 1) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180
            ]
        )
        guard writer.canAdd(input) else { throw SyntheticMediaError.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? SyntheticMediaError.writerFailed }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                await Task.yield()
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferCreate(
                nil,
                320,
                180,
                kCVPixelFormatType_32BGRA,
                nil,
                &optionalBuffer
            ) == kCVReturnSuccess, let buffer = optionalBuffer else {
                throw SyntheticMediaError.pixelBufferFailed
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<180 {
                    for x in 0..<320 {
                        let offset = y * rowBytes + x * 4
                        bytes[offset] = UInt8((x + frame * 2) % 255)
                        bytes[offset + 1] = UInt8((y * 2) % 255)
                        bytes[offset + 2] = 96
                        bytes[offset + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? SyntheticMediaError.writerFailed
            }
        }
        input.markAsFinished()
        let writerBox = AssetWriterBox(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writerBox.writer.finishWriting {
                if writerBox.writer.status == .completed { continuation.resume() }
                else {
                    continuation.resume(throwing: writerBox.writer.error ?? SyntheticMediaError.writerFailed)
                }
            }
        }
    }

    static func makeAudio(at url: URL, seconds: Int = 1) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(44_100 * seconds)
              ), let samples = buffer.floatChannelData?[0] else {
            throw SyntheticMediaError.audioBufferFailed
        }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = sin(Float(frame) * 2 * .pi * 440 / 44_100) * 0.25
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func makeAudioWithLeadingSilence(at url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200),
              let samples = buffer.floatChannelData?[0] else {
            throw SyntheticMediaError.audioBufferFailed
        }
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = frame < 44_100 ? 0 : sin(Float(frame) * 2 * .pi * 440 / 44_100) * 0.25
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func makeAudioWithBeats(at url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200),
              let samples = buffer.floatChannelData?[0] else {
            throw SyntheticMediaError.audioBufferFailed
        }
        buffer.frameLength = buffer.frameCapacity
        let beatFrames = [22_050, 44_100, 66_150]
        for frame in 0..<Int(buffer.frameLength) {
            let isBeat = beatFrames.contains { frame >= $0 && frame < $0 + 882 }
            samples[frame] = isBeat
                ? sin(Float(frame) * 2 * .pi * 120 / 44_100) * 0.9
                : sin(Float(frame) * 2 * .pi * 220 / 44_100) * 0.01
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
