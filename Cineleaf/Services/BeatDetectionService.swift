import CineleafCore
import Foundation

enum BeatDetectionError: Error {
    case noBeats
}

actor BeatDetectionService {
    func detect(
        url: URL,
        sourceStart: RationalTime,
        sourceDuration: RationalTime,
        windowDuration: Double = 0.05
    ) async throws -> [RationalTime] {
        var energies: [Float] = []
        var squaredSum = 0.0
        var sampleCount = 0
        var samplesPerWindow = 1

        try await StreamingAudioReader.read(
            url: url,
            sourceStart: sourceStart,
            sourceDuration: sourceDuration
        ) { samples, format in
            samplesPerWindow = max(Int(format.sampleRate * Double(format.channelCount) * windowDuration), 1)
            for sample in samples {
                squaredSum += Double(sample * sample)
                sampleCount += 1
                if sampleCount == samplesPerWindow {
                    energies.append(Float(sqrt(squaredSum / Double(sampleCount))))
                    squaredSum = 0
                    sampleCount = 0
                }
            }
        }
        if sampleCount > 0 { energies.append(Float(sqrt(squaredSum / Double(sampleCount)))) }
        let beats = BeatMarkerDetector.detect(
            energies: energies,
            windowDuration: RationalTime(seconds: windowDuration, preferredTimescale: 60_000)
        )
        guard !beats.isEmpty else { throw BeatDetectionError.noBeats }
        return beats
    }
}
