import CineleafCore
import Foundation

enum SilenceDetectionError: Error {
    case unsupportedFormat
    case noAudio
}

actor SilenceDetectionService {
    func detect(
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        thresholdDecibels: Double = -40,
        minimumDuration: Double = 0.5,
        windowDuration: Double = 0.1
    ) async throws -> [RationalTimeRange] {
        var ranges: [RationalTimeRange] = []
        var processedSamples: Int64 = 0
        var silenceStart: Int64?
        var sampleRate = 0.0
        var channelCount = 1
        var samplesPerWindow = 1
        var windowSum = 0.0
        var windowSamples = 0

        func closeSilence(at endSample: Int64) {
            guard let start = silenceStart else { return }
            let samplesPerSecond = sampleRate * Double(channelCount)
            let duration = Double(endSample - start) / samplesPerSecond
            if duration >= minimumDuration {
                ranges.append(RationalTimeRange(
                    start: sourceStart + RationalTime(seconds: Double(start) / samplesPerSecond, preferredTimescale: 6_000),
                    duration: RationalTime(seconds: duration, preferredTimescale: 6_000)
                ))
            }
            silenceStart = nil
        }

        try await StreamingAudioReader.read(url: url, sourceStart: sourceStart, sourceDuration: sourceDuration) {
            samples, format in
            sampleRate = format.sampleRate
            channelCount = format.channelCount
            samplesPerWindow = max(Int(sampleRate * Double(channelCount) * windowDuration), 1)
            for sample in samples {
                windowSum += Double(sample * sample)
                windowSamples += 1
                if windowSamples == samplesPerWindow {
                    let decibels = windowSum > 0 ? 20 * log10(sqrt(windowSum / Double(windowSamples))) : -Double.infinity
                    if decibels <= thresholdDecibels {
                        if silenceStart == nil { silenceStart = processedSamples }
                    } else {
                        closeSilence(at: processedSamples)
                    }
                    processedSamples += Int64(windowSamples)
                    windowSamples = 0
                    windowSum = 0
                }
            }
        }
        if windowSamples > 0 {
            let decibels = windowSum > 0 ? 20 * log10(sqrt(windowSum / Double(windowSamples))) : -Double.infinity
            if decibels <= thresholdDecibels {
                if silenceStart == nil { silenceStart = processedSamples }
            } else {
                closeSilence(at: processedSamples)
            }
            processedSamples += Int64(windowSamples)
        }
        guard sampleRate > 0, processedSamples > 0 else { throw SilenceDetectionError.noAudio }
        closeSilence(at: processedSamples)
        return ranges
    }
}
