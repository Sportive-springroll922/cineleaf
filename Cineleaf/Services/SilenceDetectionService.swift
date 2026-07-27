import AVFAudio
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
    ) throws -> [RationalTimeRange] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.commonFormat == .pcmFormatFloat32 else { throw SilenceDetectionError.unsupportedFormat }
        let startFrame = max(AVAudioFramePosition((sourceStart.seconds * format.sampleRate).rounded()), 0)
        var remaining = min(
            AVAudioFramePosition((sourceDuration.seconds * format.sampleRate).rounded()),
            max(file.length - startFrame, 0)
        )
        guard remaining > 0 else { throw SilenceDetectionError.noAudio }
        file.framePosition = startFrame
        let windowFrames = max(AVAudioFrameCount((windowDuration * format.sampleRate).rounded()), 1)
        var ranges: [RationalTimeRange] = []
        var processedFrames: AVAudioFramePosition = 0
        var silenceStart: AVAudioFramePosition?

        func closeSilence(at endFrame: AVAudioFramePosition) {
            guard let start = silenceStart else { return }
            let duration = Double(endFrame - start) / format.sampleRate
            if duration >= minimumDuration {
                ranges.append(RationalTimeRange(
                    start: sourceStart + RationalTime(seconds: Double(start) / format.sampleRate, preferredTimescale: 6_000),
                    duration: RationalTime(seconds: duration, preferredTimescale: 6_000)
                ))
            }
            silenceStart = nil
        }

        while remaining > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(remaining, AVAudioFramePosition(windowFrames)))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let channels = buffer.floatChannelData else { throw SilenceDetectionError.unsupportedFormat }
            try file.read(into: buffer, frameCount: count)
            var sum = 0.0
            let samples = Int(buffer.frameLength) * Int(format.channelCount)
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(channels[channel][frame])
                    sum += value * value
                }
            }
            let decibels = samples > 0 && sum > 0 ? 20 * log10(sqrt(sum / Double(samples))) : -Double.infinity
            if decibels <= thresholdDecibels {
                if silenceStart == nil { silenceStart = processedFrames }
            } else {
                closeSilence(at: processedFrames)
            }
            processedFrames += AVAudioFramePosition(buffer.frameLength)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        closeSilence(at: processedFrames)
        return ranges
    }
}
