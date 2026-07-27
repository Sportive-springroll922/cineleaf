import Foundation

public struct RationalTime: Codable, Hashable, Sendable, Comparable {
    public static let zero = RationalTime(value: 0, timescale: 1)

    public let value: Int64
    public let timescale: Int32

    public init(value: Int64, timescale: Int32) {
        precondition(timescale > 0, "Timescale must be positive")
        precondition(value != Int64.min, "Unsupported time magnitude")
        let divisor = Self.greatestCommonDivisor(abs(value), Int64(timescale))
        self.value = value / divisor
        self.timescale = Int32(Int64(timescale) / divisor)
    }

    public init(seconds: Double, preferredTimescale: Int32 = 600) {
        precondition(seconds.isFinite, "Time must be finite")
        precondition(preferredTimescale > 0, "Timescale must be positive")
        self.init(value: Int64((seconds * Double(preferredTimescale)).rounded()), timescale: preferredTimescale)
    }

    public var seconds: Double {
        Double(value) / Double(timescale)
    }

    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        let (left, leftOverflow) = lhs.value.multipliedReportingOverflow(by: Int64(rhs.timescale))
        let (right, rightOverflow) = rhs.value.multipliedReportingOverflow(by: Int64(lhs.timescale))
        if !leftOverflow && !rightOverflow {
            return left < right
        }
        return lhs.seconds < rhs.seconds
    }

    public static func + (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        let common = commonTimescale(lhs.timescale, rhs.timescale)
        let leftMultiplier = Int64(common / lhs.timescale)
        let rightMultiplier = Int64(common / rhs.timescale)
        let (left, leftOverflow) = lhs.value.multipliedReportingOverflow(by: leftMultiplier)
        let (right, rightOverflow) = rhs.value.multipliedReportingOverflow(by: rightMultiplier)
        let (sum, additionOverflow) = left.addingReportingOverflow(right)
        precondition(!leftOverflow && !rightOverflow && !additionOverflow, "Time arithmetic overflow")
        return RationalTime(value: sum, timescale: common)
    }

    public static func - (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        lhs + RationalTime(value: -rhs.value, timescale: rhs.timescale)
    }

    public static prefix func - (time: RationalTime) -> RationalTime {
        RationalTime(value: -time.value, timescale: time.timescale)
    }

    public static func * (lhs: RationalTime, rhs: Int64) -> RationalTime {
        let (value, overflow) = lhs.value.multipliedReportingOverflow(by: rhs)
        precondition(!overflow, "Time arithmetic overflow")
        return RationalTime(value: value, timescale: lhs.timescale)
    }

    public func clamped(to range: ClosedRange<RationalTime>) -> RationalTime {
        min(max(self, range.lowerBound), range.upperBound)
    }

    public static func absolute(_ time: RationalTime) -> RationalTime {
        time.value < 0 ? -time : time
    }

    private static func commonTimescale(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        let divisor = greatestCommonDivisor(Int64(lhs), Int64(rhs))
        let candidate = Int64(lhs) / divisor * Int64(rhs)
        precondition(candidate <= Int64(Int32.max), "Timescale overflow")
        return Int32(candidate)
    }

    private static func greatestCommonDivisor(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}

public struct RationalTimeRange: Codable, Hashable, Sendable {
    public var start: RationalTime
    public var duration: RationalTime

    public init(start: RationalTime, duration: RationalTime) {
        self.start = start
        self.duration = duration
    }

    public var end: RationalTime { start + duration }

    public func contains(_ time: RationalTime) -> Bool {
        time >= start && time < end
    }

    public func intersects(_ other: RationalTimeRange) -> Bool {
        start < other.end && other.start < end
    }
}

public struct RationalRate: Codable, Hashable, Sendable {
    public let numerator: Int32
    public let denominator: Int32

    public init(numerator: Int32, denominator: Int32 = 1) {
        precondition(numerator > 0 && denominator > 0, "Frame rate must be positive")
        self.numerator = numerator
        self.denominator = denominator
    }

    public var framesPerSecond: Double {
        Double(numerator) / Double(denominator)
    }

    public var frameDuration: RationalTime {
        RationalTime(value: Int64(denominator), timescale: numerator)
    }
}

