import AVFoundation
import CineleafCore
import Foundation

enum StreamingAudioError: Error {
    case noAudioTrack
    case unsupportedFormat
    case cannotRead
}

struct StreamingAudioFormat: Sendable {
    let sampleRate: Double
    let channelCount: Int
}

enum StreamingAudioReader {
    static func read(
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        consume: (UnsafeBufferPointer<Float>, StreamingAudioFormat) -> Void
    ) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw StreamingAudioError.noAudioTrack
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            throw StreamingAudioError.unsupportedFormat
        }
        let format = StreamingAudioFormat(
            sampleRate: basic.pointee.mSampleRate,
            channelCount: max(Int(basic.pointee.mChannelsPerFrame), 1)
        )
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: sourceStart.cmTime, duration: sourceDuration.cmTime)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw StreamingAudioError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? StreamingAudioError.cannotRead }

        do {
            while reader.status == .reading {
                try Task.checkCancellation()
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                autoreleasepool {
                    guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
                    var lengthAtOffset = 0
                    var totalLength = 0
                    var pointer: UnsafeMutablePointer<Int8>?
                    guard CMBlockBufferGetDataPointer(
                        block,
                        atOffset: 0,
                        lengthAtOffsetOut: &lengthAtOffset,
                        totalLengthOut: &totalLength,
                        dataPointerOut: &pointer
                    ) == kCMBlockBufferNoErr, let pointer else { return }
                    let count = totalLength / MemoryLayout<Float>.size
                    consume(UnsafeBufferPointer(
                        start: UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self),
                        count: count
                    ), format)
                }
            }
            if reader.status == .failed { throw reader.error ?? StreamingAudioError.cannotRead }
            try Task.checkCancellation()
        } catch {
            reader.cancelReading()
            throw error
        }
    }
}
