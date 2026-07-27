import XCTest
@testable import CineleafCore

final class PersistenceTests: XCTestCase {
    func testProjectSerializationRoundTrip() throws {
        let fixture = TestFixtures.projectWithClip()
        let codec = ProjectCodec()

        let decoded = try codec.decode(codec.encode(fixture.project))

        XCTAssertEqual(decoded, fixture.project)
    }

    func testVersionZeroMigrationDoesNotMutateInput() throws {
        let fixture = TestFixtures.projectWithClip()
        let codec = ProjectCodec()
        let current = try codec.encode(fixture.project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["formatVersion"] = 0
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try codec.decode(legacy)

        XCTAssertEqual(decoded.formatVersion, CineleafProject.currentFormatVersion)
        let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        XCTAssertEqual(originalObject["formatVersion"] as? Int, 0)
    }

    func testVersionOneMigrationAddsAdvancedEditingDefaults() throws {
        let fixture = TestFixtures.projectWithClip()
        let current = try ProjectCodec().encode(fixture.project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["formatVersion"] = 1
        var timeline = try XCTUnwrap(object["timeline"] as? [String: Any])
        var tracks = try XCTUnwrap(timeline["tracks"] as? [[String: Any]])
        var clips = try XCTUnwrap(tracks[0]["clips"] as? [[String: Any]])
        for key in ["playbackRate", "isReversed", "role", "colorAdjustments", "effects", "keyframes"] {
            clips[0].removeValue(forKey: key)
        }
        tracks[0]["clips"] = clips
        timeline["tracks"] = tracks
        object["timeline"] = timeline
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let migrated = try ProjectCodec().decode(legacy)
        let clip = try XCTUnwrap(migrated.timeline.tracks[0].clips.first)

        XCTAssertEqual(migrated.formatVersion, CineleafProject.currentFormatVersion)
        XCTAssertEqual(clip.playbackRate, 1)
        XCTAssertEqual(clip.effects, [])
        XCTAssertEqual(clip.keyframes, ClipKeyframes())
    }

    func testRejectsFutureProjectWithoutRewriting() throws {
        let fixture = TestFixtures.projectWithClip()
        let current = try ProjectCodec().encode(fixture.project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["formatVersion"] = 999
        let future = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try ProjectCodec().decode(future)) { error in
            XCTAssertEqual(error as? ProjectPersistenceError, .unsupportedFutureVersion(999))
        }
    }

    func testPackageSaveAndReopen() async throws {
        let fixture = TestFixtures.projectWithClip()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let package = root.appendingPathComponent("Fixture.cineleaf", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectPackageStore(recoveryDirectory: root.appendingPathComponent("Recovery", isDirectory: true))

        try await store.save(fixture.project, to: package)
        let reopened = try await store.open(package)

        XCTAssertEqual(reopened, fixture.project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("project.json").path))
    }

    func testRecoveryRoundTripAndDiscard() async throws {
        let project = CineleafProject(name: "Recovery")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectPackageStore(recoveryDirectory: root)

        try await store.saveRecovery(project)
        let recovered = try await store.availableRecoveries()
        XCTAssertEqual(recovered, [project])
        try await store.discardRecovery(projectID: project.id)
        let remaining = try await store.availableRecoveries()
        XCTAssertEqual(remaining, [])
    }

    func testFilenameSanitization() {
        XCTAssertEqual(FilenameSanitizer.sanitize("  My:/Movie?.mov  "), "My--Movie-.mov")
        XCTAssertEqual(FilenameSanitizer.sanitize("..."), "Cineleaf Export")
        XCTAssertLessThanOrEqual(FilenameSanitizer.sanitize(String(repeating: "a", count: 500)).count, 120)
    }
}
