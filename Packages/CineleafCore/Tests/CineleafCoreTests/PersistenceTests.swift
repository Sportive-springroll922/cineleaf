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
