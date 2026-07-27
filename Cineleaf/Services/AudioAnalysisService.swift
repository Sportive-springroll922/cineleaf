import AVFAudio
import CineleafCore
import Foundation

struct AudioNormalizationResult: Sendable {
    let rmsDecibels: Double
    let peakDecibels: Double
    let linearGain: Double
}

enum AudioAnalysisError: Error {
    case unsupportedFormat
    case noAudioSamples
}

actor AudioAnalysisService {
    func normalization(
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        targetRMSDecibels: Double = -16,
        peakCeilingDecibels: Double = -1
    ) throws -> AudioNormalizationResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.commonFormat == .pcmFormatFloat32 else { throw AudioAnalysisError.unsupportedFormat }
        let startFrame = max(AVAudioFramePosition((sourceStart.seconds * format.sampleRate).rounded()), 0)
        var remaining = min(
            AVAudioFramePosition((sourceDuration.seconds * format.sampleRate).rounded()),
            max(file.length - startFrame, 0)
        )
        file.framePosition = startFrame
        let capacity: AVAudioFrameCount = 32_768
        var squaredSum = 0.0
        var peak = 0.0
        var sampleCount: Int64 = 0

        while remaining > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(remaining, AVAudioFramePosition(capacity)))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let channels = buffer.floatChannelData else { throw AudioAnalysisError.unsupportedFormat }
            try file.read(into: buffer, frameCount: count)
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = Double(channels[channel][frame])
                    squaredSum += sample * sample
                    peak = max(peak, abs(sample))
                }
            }
            sampleCount += Int64(buffer.frameLength) * Int64(format.channelCount)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        guard sampleCount > 0, squaredSum > 0, peak > 0 else { throw AudioAnalysisError.noAudioSamples }
        let rms = sqrt(squaredSum / Double(sampleCount))
        let rmsDB = 20 * log10(rms)
        let peakDB = 20 * log10(peak)
        let gainDB = min(targetRMSDecibels - rmsDB, peakCeilingDecibels - peakDB)
        return AudioNormalizationResult(
            rmsDecibels: rmsDB,
            peakDecibels: peakDB,
            linearGain: min(max(pow(10, gainDB / 20), 0), 2)
        )
    }
}
