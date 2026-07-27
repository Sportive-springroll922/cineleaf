import Foundation

public enum InterpolationCurve: String, Codable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    public func apply(to progress: Double) -> Double {
        let value = min(max(progress, 0), 1)
        switch self {
        case .linear:
            return value
        case .easeIn:
            return value * value
        case .easeOut:
            return 1 - (1 - value) * (1 - value)
        case .easeInOut:
            return value * value * (3 - 2 * value)
        }
    }
}

public struct ScalarKeyframe: Codable, Hashable, Sendable {
    public var time: RationalTime
    public var value: Double
    public var curve: InterpolationCurve

    public init(time: RationalTime, value: Double, curve: InterpolationCurve = .linear) {
        self.time = time
        self.value = value
        self.curve = curve
    }
}

public enum KeyframeInterpolator {
    public static func value(at time: RationalTime, keyframes: [ScalarKeyframe]) -> Double? {
        let ordered = keyframes.sorted { $0.time < $1.time }
        guard let first = ordered.first else { return nil }
        guard time > first.time else { return first.value }
        guard let last = ordered.last, time < last.time else { return ordered.last?.value }

        guard let upperIndex = ordered.firstIndex(where: { $0.time >= time }), upperIndex > 0 else {
            return last.value
        }
        let lower = ordered[upperIndex - 1]
        let upper = ordered[upperIndex]
        let span = (upper.time - lower.time).seconds
        guard span > 0 else { return upper.value }
        let rawProgress = (time - lower.time).seconds / span
        let progress = lower.curve.apply(to: rawProgress)
        return lower.value + (upper.value - lower.value) * progress
    }

    public static func transform(
        from start: ClipTransform,
        to end: ClipTransform,
        progress: Double,
        curve: InterpolationCurve = .linear
    ) -> ClipTransform {
        let value = curve.apply(to: progress)
        func interpolate(_ lhs: Double, _ rhs: Double) -> Double { lhs + (rhs - lhs) * value }
        return ClipTransform(
            positionX: interpolate(start.positionX, end.positionX),
            positionY: interpolate(start.positionY, end.positionY),
            scale: interpolate(start.scale, end.scale),
            rotationDegrees: interpolate(start.rotationDegrees, end.rotationDegrees),
            cropTop: interpolate(start.cropTop, end.cropTop),
            cropLeading: interpolate(start.cropLeading, end.cropLeading),
            cropBottom: interpolate(start.cropBottom, end.cropBottom),
            cropTrailing: interpolate(start.cropTrailing, end.cropTrailing),
            contentMode: value < 0.5 ? start.contentMode : end.contentMode
        )
    }
}
