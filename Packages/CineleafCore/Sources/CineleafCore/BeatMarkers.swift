import Foundation

public enum BeatMarkerDetector {
    public static func detect(
        energies: [Float],
        windowDuration: RationalTime,
        sensitivity: Float = 1.45,
        minimumSpacing: RationalTime = RationalTime(value: 1, timescale: 4)
    ) -> [RationalTime] {
        guard energies.count >= 3, windowDuration > .zero, sensitivity > 1 else { return [] }

        let radius = 8
        var prefix = [Double](repeating: 0, count: energies.count + 1)
        for index in energies.indices {
            prefix[index + 1] = prefix[index] + Double(max(energies[index], 0))
        }

        var candidates: [(time: RationalTime, strength: Float)] = []
        candidates.reserveCapacity(energies.count / 8)
        for index in 1..<(energies.count - 1) {
            let lower = max(0, index - radius)
            let upper = min(energies.count, index + radius + 1)
            let neighborCount = max(upper - lower - 1, 1)
            let neighborTotal = prefix[upper] - prefix[lower] - Double(energies[index])
            let localAverage = Float(neighborTotal / Double(neighborCount))
            let energy = energies[index]
            guard energy >= 0.015,
                  energy > energies[index - 1], energy >= energies[index + 1],
                  energy >= max(localAverage * sensitivity, energies[index - 1] * 1.12) else { continue }
            candidates.append((windowDuration * Int64(index), energy))
        }

        var accepted: [(time: RationalTime, strength: Float)] = []
        for candidate in candidates {
            if let last = accepted.last, candidate.time - last.time < minimumSpacing {
                if candidate.strength > last.strength { accepted[accepted.count - 1] = candidate }
            } else {
                accepted.append(candidate)
            }
        }
        return accepted.map(\.time)
    }
}
