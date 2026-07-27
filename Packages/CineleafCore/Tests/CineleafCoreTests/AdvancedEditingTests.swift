import XCTest
@testable import CineleafCore

final class AdvancedEditingTests: XCTestCase {
    func testRippleDeleteClosesOnlyDeletedGap() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)

        try editor.rippleDelete([fixture.clips[1].id])

        let clips = editor.project.timeline.tracks[0].clips
        XCTAssertEqual(clips.map(\.id), [fixture.clips[0].id, fixture.clips[2].id])
        XCTAssertEqual(clips[1].timelineStart, RationalTime(value: 10, timescale: 1))
    }

    func testGroupAndLinkAssignSharedIdentifiers() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)
        let ids = Set(fixture.clips.prefix(2).map(\.id))

        let groupID = try editor.groupClips(ids)
        let linkID = try editor.linkClips(ids)

        let updated = editor.project.timeline.tracks[0].clips.filter { ids.contains($0.id) }
        XCTAssertEqual(Set(updated.compactMap(\.groupID)), Set([groupID]))
        XCTAssertEqual(Set(updated.compactMap(\.linkGroupID)), Set([linkID]))
    }

    func testPlaybackRatePreservesSourceRangeAndRipplesLaterClips() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)

        try editor.setPlaybackRate(fixture.clips[0].id, rate: 2, ripple: true)

        let clips = editor.project.timeline.tracks[0].clips
        XCTAssertEqual(clips[0].duration, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(clips[1].timelineStart, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(clips[2].timelineStart, RationalTime(value: 15, timescale: 1))
        XCTAssertEqual(clips[0].playbackRate, 2)
    }

    func testKeyframeAtSameTimeReplacesPreviousValue() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)
        let time = RationalTime(value: 2, timescale: 1)

        try editor.setKeyframe(.opacity, ScalarKeyframe(time: time, value: 0.25), for: fixture.clips[0].id)
        try editor.setKeyframe(.opacity, ScalarKeyframe(time: time, value: 0.75), for: fixture.clips[0].id)

        let clip = try XCTUnwrap(editor.project.timeline.tracks[0].clips.first)
        XCTAssertEqual(clip.keyframes.opacity, [ScalarKeyframe(time: time, value: 0.75)])
    }

    func testEffectsAndTransitionsSurviveSerialization() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)
        let clipID = fixture.clips[0].id
        let adjustments = ColorAdjustments(exposure: 0.5, contrast: 1.2, saturation: 0.8)
        let effect = VideoEffect(kind: .vignette, amount: 0.6)
        let transition = ClipTransition(kind: .fadeThroughBlack, duration: RationalTime(value: 1, timescale: 2))

        try editor.setColorAdjustments(adjustments, for: clipID)
        try editor.addEffect(effect, to: clipID)
        try editor.setTransition(transition, edge: .out, for: clipID)
        let decoded = try ProjectCodec().decode(ProjectCodec().encode(editor.project))

        let clip = try XCTUnwrap(decoded.timeline.tracks[0].clips.first)
        XCTAssertEqual(clip.colorAdjustments, adjustments)
        XCTAssertEqual(clip.effects, [effect])
        XCTAssertEqual(clip.transitionOut, transition)
    }

    func testTimelineIndexReturnsOnlyIntersectingClips() {
        let fixture = threeClipProject()
        let index = TimelineIndex(timeline: fixture.project.timeline)

        let visible = index.clips(
            in: RationalTimeRange(
                start: RationalTime(value: 12, timescale: 1),
                duration: RationalTime(value: 5, timescale: 1)
            ),
            trackID: fixture.project.timeline.tracks[0].id
        )

        XCTAssertEqual(visible.map(\.id), [fixture.clips[1].id])
    }

    func testSubtitleParserSupportsSRTAndWebVTT() throws {
        let srt = """
        1
        00:00:01,250 --> 00:00:03,500
        Hello world

        2
        00:00:04,000 --> 00:00:05,000
        Second line
        """
        let webVTT = """
        WEBVTT

        00:00:00.500 --> 00:00:02.000
        Hola
        """

        let srtCues = try SubtitleParser.parse(srt, format: .srt)
        let vttCues = try SubtitleParser.parse(webVTT, format: .webVTT)

        XCTAssertEqual(srtCues.count, 2)
        XCTAssertEqual(srtCues[0].start.seconds, 1.25, accuracy: 0.001)
        XCTAssertEqual(srtCues[0].text, "Hello world")
        XCTAssertEqual(try XCTUnwrap(vttCues.first).duration.seconds, 1.5, accuracy: 0.001)
        XCTAssertTrue(SubtitleParser.serialize(srtCues, format: .webVTT).hasPrefix("WEBVTT"))
    }

    func testInsertEditShiftsLaterClips() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)
        let inserted = TimelineClip(
            name: "Title",
            kind: .text,
            timelineStart: .zero,
            duration: RationalTime(value: 2, timescale: 1),
            textStyle: TextStyle(text: "Title")
        )

        try editor.insertEdit(inserted, into: fixture.project.timeline.tracks[0].id, at: RationalTime(value: 10, timescale: 1))

        let clips = editor.project.timeline.tracks[0].clips
        XCTAssertEqual(clips.first(where: { $0.id == inserted.id })?.timelineStart, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(clips.first(where: { $0.id == fixture.clips[1].id })?.timelineStart, RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(clips.first(where: { $0.id == fixture.clips[2].id })?.timelineStart, RationalTime(value: 22, timescale: 1))
    }

    func testOverwriteEditPreservesNonOverwrittenSides() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)
        let replacement = TimelineClip(
            name: "Replacement",
            kind: .text,
            timelineStart: .zero,
            duration: RationalTime(value: 4, timescale: 1),
            textStyle: TextStyle(text: "Replacement")
        )

        try editor.overwriteEdit(replacement, into: fixture.project.timeline.tracks[0].id, at: RationalTime(value: 8, timescale: 1))

        let clips = editor.project.timeline.tracks[0].clips
        XCTAssertEqual(clips.first(where: { $0.id == fixture.clips[0].id })?.duration, RationalTime(value: 8, timescale: 1))
        XCTAssertEqual(clips.first(where: { $0.id == replacement.id })?.timelineStart, RationalTime(value: 8, timescale: 1))
        let rightRemainder = try XCTUnwrap(clips.first(where: { $0.name == fixture.clips[1].name && $0.id != fixture.clips[1].id }))
        XCTAssertEqual(rightRemainder.timelineStart, RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(rightRemainder.duration, RationalTime(value: 8, timescale: 1))
        XCTAssertEqual(rightRemainder.sourceStart, RationalTime(value: 12, timescale: 1))
    }

    func testMovingGroupedClipsPreservesTheirOffsets() throws {
        let fixture = threeClipProject()
        var editor = try ProjectEditor(project: fixture.project)
        _ = try editor.groupClips(Set(fixture.clips.suffix(2).map(\.id)))

        try editor.moveClip(fixture.clips[1].id, to: RationalTime(value: 12, timescale: 1))

        let clips = editor.project.timeline.tracks[0].clips
        XCTAssertEqual(clips.first(where: { $0.id == fixture.clips[1].id })?.timelineStart, RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(clips.first(where: { $0.id == fixture.clips[2].id })?.timelineStart, RationalTime(value: 22, timescale: 1))
    }

    func testAutomaticCaptionBuilderCreatesReadableTimedCues() {
        let tokens = [
            TranscriptToken(text: "Hello", start: .zero, duration: RationalTime(value: 1, timescale: 2)),
            TranscriptToken(text: "world.", start: RationalTime(value: 1, timescale: 2), duration: RationalTime(value: 1, timescale: 2)),
            TranscriptToken(text: "This", start: RationalTime(value: 2, timescale: 1), duration: RationalTime(value: 1, timescale: 2)),
            TranscriptToken(text: "continues", start: RationalTime(value: 5, timescale: 2), duration: RationalTime(value: 1, timescale: 2))
        ]

        let cues = AutomaticCaptionBuilder.cues(from: tokens, maximumCharacters: 20, maximumDuration: 3)

        XCTAssertEqual(cues.map(\.text), ["Hello world.", "This continues"])
        XCTAssertEqual(cues[0].duration, RationalTime(value: 1, timescale: 1))
        XCTAssertEqual(cues[1].start, RationalTime(value: 2, timescale: 1))
    }

    private func threeClipProject() -> (project: CineleafProject, clips: [TimelineClip]) {
        let asset = TestFixtures.asset(duration: RationalTime(value: 30, timescale: 1))
        var project = CineleafProject(name: "Advanced", assets: [asset])
        let clips = (0..<3).map { index in
            TimelineClip(
                name: "Clip \(index)",
                kind: .video,
                assetID: asset.id,
                timelineStart: RationalTime(value: Int64(index * 10), timescale: 1),
                duration: RationalTime(value: 10, timescale: 1),
                sourceStart: RationalTime(value: Int64(index * 10), timescale: 1)
            )
        }
        project.timeline.tracks[0].clips = clips
        return (project, clips)
    }
}
