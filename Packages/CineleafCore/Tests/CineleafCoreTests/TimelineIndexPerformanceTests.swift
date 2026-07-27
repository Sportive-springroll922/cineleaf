import XCTest
@testable import CineleafCore

final class TimelineIndexPerformanceTests: XCTestCase {
    func testVisibleRangeQueryPerformanceWithTenThousandClips() {
        let track = TimelineTrack(
            name: "V1",
            kind: .video,
            clips: (0..<10_000).map { index in
                TimelineClip(
                    name: "Clip \(index)",
                    kind: .text,
                    timelineStart: RationalTime(value: Int64(index * 2), timescale: 1),
                    duration: RationalTime(value: 1, timescale: 1),
                    textStyle: TextStyle(text: "Frame")
                )
            }
        )
        let index = TimelineIndex(timeline: Timeline(tracks: [track]))
        let visible = RationalTimeRange(
            start: RationalTime(value: 10_000, timescale: 1),
            duration: RationalTime(value: 30, timescale: 1)
        )

        measure {
            XCTAssertEqual(index.clips(in: visible, trackID: track.id).count, 15)
        }
    }
}
