import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation
import CineleafCore

enum WaveformError: Error {
    case noAudioTrack
    case cannotReadAudio
    case invalidAudioFormat
}

actor AVWaveformGenerator: WaveformGenerating {
    private let cache = BoundedCache<String, [Float]>(limit: 64)
    private let diskCache = DerivedDataCache.shared
    private var activeReaders: [UUID: AVAssetReader] = [:]

    func waveform(for request: WaveformRequest, url: URL) async throws -> [Float] {
        guard request.sampleCount > 0 else { return [] }
        let key = try cacheKey(request: request, url: url)
        if let cached = await cache.value(for: key) { return cached }
        if let data = try? await diskCache.data(for: "waveform|\(key)"),
           let diskPeaks = try? PropertyListDecoder().decode([Float].self, from: data) {
            await cache.insert(diskPeaks, for: key)
            return diskPeaks
        }
        let peaks = try await LocalDiagnostics.shared.measure("waveform_generation") {
            try Task.checkCancellation()
            return try await self.generate(request: request, url: url)
        }
        await cache.insert(peaks, for: key)
        if let data = try? PropertyListEncoder().encode(peaks) {
            try? await diskCache.store(data, for: "waveform|\(key)")
        }
        return peaks
    }

    func cancel(assetID: UUID) {
        activeReaders[assetID]?.cancelReading()
        activeReaders.removeValue(forKey: assetID)
    }

    func clearCache() async { await cache.removeAll() }

    private func generate(request: WaveformRequest, url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }
        let duration = try await asset.load(.duration)
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            throw WaveformError.invalidAudioFormat
        }
        let channels = max(Int(basic.pointee.mChannelsPerFrame), 1)
        let expectedValues = max(Int(duration.seconds * basic.pointee.mSampleRate) * channels, 1)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WaveformError.cannotReadAudio }
        reader.add(output)
        activeReaders[request.assetID]?.cancelReading()
        activeReaders[request.assetID] = reader
        defer { activeReaders.removeValue(forKey: request.assetID) }
        guard reader.startReading() else { throw reader.error ?? WaveformError.cannotReadAudio }

        var peaks = [Float](repeating: 0, count: request.sampleCount)
        var processed = 0
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
                let valueCount = totalLength / MemoryLayout<Float>.size
                let values = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
                for index in 0..<valueCount {
                    let target = min((processed + index) * request.sampleCount / expectedValues, request.sampleCount - 1)
                    peaks[target] = max(peaks[target], min(abs(values[index]), 1))
                }
                processed += valueCount
            }
        }
        if reader.status == .failed { throw reader.error ?? WaveformError.cannotReadAudio }
        try Task.checkCancellation()
        return peaks
    }

    private func cacheKey(request: WaveformRequest, url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            request.assetID.uuidString,
            "\(request.sampleCount)",
            "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)",
            "\(values.fileSize ?? 0)"
        ].joined(separator: "|")
    }
}
