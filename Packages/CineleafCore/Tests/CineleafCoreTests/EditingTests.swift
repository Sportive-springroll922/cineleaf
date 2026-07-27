import XCTest
@testable import CineleafCore

final class EditingTests: XCTestCase {
    func testSplitPreservesDurationAndSourceContinuity() throws {
        let fixture = TestFixtures.projectWithClip()
        var editor = try ProjectEditor(project: fixture.project)
        let splitTime = RationalTime(value: 4, timescale: 1)

        let secondID = try editor.splitClip(fixture.clip.id, at: splitTime)
        let clips = editor.project.timeline.tracks[0].clips

        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].duration, splitTime)
        XCTAssertEqual(clips[1].id, secondID)
        XCTAssertEqual(clips[1].timelineStart, splitTime)
        XCTAssertEqual(clips[1].sourceStart, splitTime)
        XCTAssertEqual(clips[0].duration + clips[1].duration, fixture.clip.duration)
    }

    func testTrimStartChangesSourceAndKeepsEnd() throws {
        let fixture = TestFixtures.projectWithClip()
        var editor = try ProjectEditor(project: fixture.project)
        let newStart = RationalTime(value: 2, timescale: 1)

        try editor.trimStart(of: fixture.clip.id, to: newStart)
        let clip = try XCTUnwrap(editor.project.timeline.tracks[0].clips.first)

        XCTAssertEqual(clip.timelineStart, newStart)
        XCTAssertEqual(clip.sourceStart, newStart)
        XCTAssertEqual(clip.duration, RationalTime(value: 8, timescale: 1))
        XCTAssertEqual(clip.timelineEnd, RationalTime(value: 10, timescale: 1))
    }

    func testRejectsOverlapAndLockedTrackMutation() throws {
        let fixture = TestFixtures.projectWithClip()
        var editor = try ProjectEditor(project: fixture.project)
        let overlapping = TimelineClip(
            name: "overlap",
            kind: .video,
            assetID: fixture.asset.id,
            timelineStart: RationalTime(value: 9, timescale: 1),
            duration: RationalTime(value: 2, timescale: 1)
        )
        XCTAssertThrowsError(try editor.insert(overlapping, into: fixture.videoTrackID))

        try editor.setTrackLocked(fixture.videoTrackID, locked: true)
        XCTAssertThrowsError(try editor.deleteClips([fixture.clip.id])) { error in
            XCTAssertEqual(error as? EditingError, .trackLocked(fixture.videoTrackID))
        }
    }

    func testSnapsToNearestEdgeWithinThreshold() throws {
        let fixture = TestFixtures.projectWithClip()
        let editor = try ProjectEditor(project: fixture.project)
        let result = editor.snappedTime(
            proposed: RationalTime(value: 101, timescale: 10),
            playhead: RationalTime(value: 5, timescale: 1),
            threshold: RationalTime(value: 1, timescale: 5)
        )
        XCTAssertTrue(result.didSnap)
        XCTAssertEqual(result.time, RationalTime(value: 10, timescale: 1))
    }

    func testDetachAudioCreatesAudioClipAndMutesSourceAudio() throws {
        let fixture = TestFixtures.projectWithClip()
        var editor = try ProjectEditor(project: fixture.project)
        let audioTrackID = editor.project.timeline.tracks[1].id

        let detachedID = try editor.detachAudio(from: fixture.clip.id, to: audioTrackID)

        XCTAssertEqual(editor.project.timeline.tracks[0].clips[0].audioVolume, 0)
        let audio = try XCTUnwrap(editor.project.timeline.tracks[1].clips.first)
        XCTAssertEqual(audio.id, detachedID)
        XCTAssertEqual(audio.kind, .audio)
        XCTAssertEqual(audio.assetID, fixture.asset.id)
    }

    func testBoundedUndoAndRedo() throws {
        let first = CineleafProject(name: "First")
        var second = first
        second.name = "Second"
        var third = first
        third.name = "Third"
        var history = EditHistory(limit: 1)
        history.record(first)
        history.record(second)

        XCTAssertEqual(history.undo(current: third)?.name, "Second")
        XCTAssertFalse(history.canUndo)
        XCTAssertEqual(history.redo(current: second)?.name, "Third")
    }
}
