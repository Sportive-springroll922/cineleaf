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
    ) async throws -> AudioNormalizationResult {
        var squaredSum = 0.0
        var peak = 0.0
        var sampleCount: Int64 = 0

        try await StreamingAudioReader.read(url: url, sourceStart: sourceStart, sourceDuration: sourceDuration) {
            samples, _ in
            for value in samples {
                let sample = Double(value)
                squaredSum += sample * sample
                peak = max(peak, abs(sample))
            }
            sampleCount += Int64(samples.count)
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
