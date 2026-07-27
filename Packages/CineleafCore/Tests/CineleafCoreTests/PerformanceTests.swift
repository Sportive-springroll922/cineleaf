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
            do {
                try ProjectValidator.validate(project)
            } catch {
                XCTFail("Validation failed: \(error)")
            }
        }
    }

    func testLargeProjectSerializationPerformance() throws {
        var project = CineleafProject(name: "Serialization")
        project.assets = (0..<100).map { index in
            TestFixtures.asset(id: UUID(), kind: .video, duration: RationalTime(value: 60, timescale: 1))
        }
        measure {
            do {
                _ = try ProjectCodec().encode(project)
            } catch {
                XCTFail("Encoding failed: \(error)")
            }
        }
    }

    func testLargeProjectSaveReopenPerformance() throws {
        let project = largeTimelineProject()
        let codec = ProjectCodec()

        measure {
            do {
                let data = try codec.encode(project)
                _ = try codec.decode(data)
            } catch {
                XCTFail("Round trip failed: \(error)")
            }
        }
    }

    func testLargeProjectEditSequencePerformance() throws {
        let project = largeTimelineProject()
        let clipID = try XCTUnwrap(project.timeline.tracks.first?.clips.first?.id)

        measure {
            do {
                var editor = try ProjectEditor(project: project)
                try editor.moveClip(clipID, to: RationalTime(value: 20, timescale: 1))
                try editor.trimStart(of: clipID, to: RationalTime(value: 21, timescale: 1))
                _ = try editor.splitClip(clipID, at: RationalTime(value: 25, timescale: 1))
            } catch {
                XCTFail("Edit sequence failed: \(error)")
            }
        }
    }

    private func largeTimelineProject() -> CineleafProject {
        let asset = TestFixtures.asset(duration: RationalTime(value: 10, timescale: 1))
        var project = CineleafProject(name: "Large Performance Project", assets: [asset])
        var tracks: [TimelineTrack] = []
        for trackIndex in 0..<10 {
            let kind: TrackKind = trackIndex < 5 ? .video : .audio
            let clipKind: ClipKind = trackIndex < 5 ? .video : .audio
            let name = trackIndex < 5 ? "V\(trackIndex + 1)" : "A\(trackIndex - 4)"
            var clips: [TimelineClip] = []
            for clipIndex in 0..<10 {
                clips.append(TimelineClip(
                    name: "Clip \(trackIndex)-\(clipIndex)",
                    kind: clipKind,
                    assetID: asset.id,
                    timelineStart: RationalTime(value: Int64(clipIndex * 400), timescale: 1),
                    duration: RationalTime(value: 10, timescale: 1)
                ))
            }
            tracks.append(TimelineTrack(name: name, kind: kind, clips: clips))
        }
        project.timeline.tracks = tracks
        return project
    }
}
