import XCTest
@testable import CineleafCore

final class ValidationAndInterpolationTests: XCTestCase {
    func testTrackOrderRoundTrips() throws {
        var project = CineleafProject(name: "Order")
        project.timeline.tracks = [
            TimelineTrack(name: "V3", kind: .video),
            TimelineTrack(name: "V2", kind: .video),
            TimelineTrack(name: "A1", kind: .audio)
        ]
        let decoded = try ProjectCodec().decode(ProjectCodec().encode(project))
        XCTAssertEqual(decoded.timeline.tracks.map(\.name), ["V3", "V2", "A1"])
    }

    func testMissingMediaUsesInjectedFilesystemCheck() {
        let available = TestFixtures.asset(id: UUID())
        var missing = TestFixtures.asset(id: UUID())
        missing.reference.lastKnownPath = "/missing.mov"
        var project = CineleafProject(name: "Missing", assets: [available, missing])
        project.timeline.tracks = []

        let statuses = MissingMediaDetector.statuses(in: project) { $0 == available.reference.lastKnownPath }

        XCTAssertEqual(statuses[available.id], .available)
        XCTAssertEqual(statuses[missing.id], .missing(lastKnownPath: "/missing.mov"))
    }

    func testScalarAndTransformInterpolation() throws {
        let keyframes = [
            ScalarKeyframe(time: .zero, value: 0),
            ScalarKeyframe(time: RationalTime(value: 2, timescale: 1), value: 10)
        ]
        XCTAssertEqual(try XCTUnwrap(KeyframeInterpolator.value(
            at: RationalTime(value: 1, timescale: 1),
            keyframes: keyframes
        )), 5, accuracy: 0.0001)

        let start = ClipTransform(positionX: 0, scale: 1)
        let end = ClipTransform(positionX: 100, scale: 2)
        let result = KeyframeInterpolator.transform(from: start, to: end, progress: 0.5)
        XCTAssertEqual(result.positionX, 50, accuracy: 0.0001)
        XCTAssertEqual(result.scale, 1.5, accuracy: 0.0001)
    }

    func testExportPlanPreservesVerticalAspectAndEvenDimensions() throws {
        let fixture = TestFixtures.projectWithClip()
        var project = fixture.project
        project.canvas = Resolution(width: 1080, height: 1920)
        project.canvasPreset = .vertical9x16
        let preferences = ExportPreferences(resolution: .p1080, frameRate: .fps30)

        let plan = try ExportPlan(filename: "My:Export", project: project, preferences: preferences)

        XCTAssertEqual(plan.filename, "My-Export")
        XCTAssertEqual(plan.resolution, Resolution(width: 1080, height: 1920))
        XCTAssertTrue(plan.resolution.width.isMultiple(of: 2))
        XCTAssertTrue(plan.resolution.height.isMultiple(of: 2))
    }
}

