import XCTest
@testable import CineleafCore

final class PerformanceTests: XCTestCase {
    func testLargeTimelineValidationPerformance() throws {
        let asset = TestFixtures.asset(duration: RationalTime(value: 10, timescale: 1))
        var project = CineleafProject(name: "Performance", assets: [asset])
        project.timeline.tracks = (0..<10).map { trackIndex in
            let clips = (0..<10).map { clipIndex in
                TimelineClip(
                    name: "Clip \(clipIndex)",
                    kind: trackIndex < 5 ? .video : .audio,
                    assetID: asset.id,
                    timelineStart: RationalTime(value: Int64(clipIndex * 400), timescale: 1),
                    duration: RationalTime(value: 10, timescale: 1)
                )
            }
            return TimelineTrack(
                name: trackIndex < 5 ? "V\(trackIndex + 1)" : "A\(trackIndex - 4)",
                kind: trackIndex < 5 ? .video : .audio,
                clips: clips
            )
        }
        XCTAssertGreaterThanOrEqual(project.timeline.duration, RationalTime(value: 3_600, timescale: 1))

        measure {
            XCTAssertNoThrow(try ProjectValidator.validate(project))
        }
    }

    func testLargeProjectSerializationPerformance() throws {
        var project = CineleafProject(name: "Serialization")
        project.assets = (0..<100).map { index in
            TestFixtures.asset(id: UUID(), kind: .video, duration: RationalTime(value: 60, timescale: 1))
        }
        measure {
            XCTAssertNoThrow(try ProjectCodec().encode(project))
        }
    }
}
