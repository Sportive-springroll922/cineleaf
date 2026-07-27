import XCTest
@testable import CineleafCore

final class RationalTimeTests: XCTestCase {
    func testNormalizesAndAddsExactly() {
        let half = RationalTime(value: 30, timescale: 60)
        XCTAssertEqual(half, RationalTime(value: 1, timescale: 2))
        XCTAssertEqual(half + RationalTime(value: 1, timescale: 3), RationalTime(value: 5, timescale: 6))
    }

    func testFrameDurationRemainsRational() {
        let rate = RationalRate(numerator: 30_000, denominator: 1_001)
        XCTAssertEqual(rate.frameDuration, RationalTime(value: 1_001, timescale: 30_000))
        XCTAssertEqual(rate.frameDuration * 300, RationalTime(value: 1_001, timescale: 100))
    }

    func testRangesDoNotIntersectAtTouchingEdges() {
        let first = RationalTimeRange(start: .zero, duration: RationalTime(value: 2, timescale: 1))
        let second = RationalTimeRange(start: first.end, duration: RationalTime(value: 1, timescale: 1))
        XCTAssertFalse(first.intersects(second))
        XCTAssertTrue(first.contains(RationalTime(value: 1, timescale: 1)))
        XCTAssertFalse(first.contains(first.end))
    }
}

