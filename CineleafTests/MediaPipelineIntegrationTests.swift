import AVFoundation
import CineleafCore
import XCTest
@testable import Cineleaf

final class MediaPipelineIntegrationTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testSyntheticImportThumbnailAndWaveform() async throws {
        let videoURL = temporaryDirectory.appendingPathComponent("video.mov")
        let audioURL = temporaryDirectory.appendingPathComponent("audio.caf")
        try await SyntheticMediaFactory.makeVideo(at: videoURL)
        try SyntheticMediaFactory.makeAudio(at: audioURL)

        let inspector = AVMediaInspector()
        let video = try await inspector.inspect(url: videoURL)
        let audio = try await inspector.inspect(url: audioURL)
        XCTAssertEqual(video.kind, .video)
        XCTAssertEqual(video.metadata.resolution, Resolution(width: 320, height: 180))
        XCTAssertEqual(audio.kind, .audio)

        let thumbnail = try await AVThumbnailGenerator().thumbnail(
            for: ThumbnailRequest(assetID: UUID(), time: .zero, pixelWidth: 160, pixelHeight: 90),
            url: videoURL
        )
        XCTAssertGreaterThan(thumbnail.cgImage.width, 0)
        XCTAssertGreaterThan(thumbnail.cgImage.height, 0)

        let peaks = try await AVWaveformGenerator().waveform(
            for: WaveformRequest(assetID: UUID(), sampleCount: 100),
            url: audioURL
        )
        XCTAssertEqual(peaks.count, 100)
        XCTAssertGreaterThan(peaks.max() ?? 0, 0)
    }

    func testCompositionAndExportHaveExpectedTracksDurationAndDimensions() async throws {
        let videoURL = temporaryDirectory.appendingPathComponent("video.mov")
        let audioURL = temporaryDirectory.appendingPathComponent("audio.caf")
        let outputURL = temporaryDirectory.appendingPathComponent("export.mp4")
        try await SyntheticMediaFactory.makeVideo(at: videoURL)
        try SyntheticMediaFactory.makeAudio(at: audioURL)

        let videoAsset = MediaAsset(
            displayName: "video.mov",
            kind: .video,
            reference: MediaReference(lastKnownPath: videoURL.path),
            metadata: MediaMetadata(
                duration: RationalTime(value: 1, timescale: 1),
                resolution: Resolution(width: 320, height: 180),
                frameRate: RationalRate(numerator: 30),
                fileType: "mov",
                hasAudio: false,
                fileSize: 1
            )
        )
        let audioAsset = MediaAsset(
            displayName: "audio.caf",
            kind: .audio,
            reference: MediaReference(lastKnownPath: audioURL.path),
            metadata: MediaMetadata(
                duration: RationalTime(value: 1, timescale: 1),
                fileType: "caf",
                hasAudio: true,
                fileSize: 1
            )
        )
        var project = CineleafProject(name: "Export")
        project.assets = [videoAsset, audioAsset]
        project.timeline.tracks[0].clips = [TimelineClip(
            name: videoAsset.displayName,
            kind: .video,
            assetID: videoAsset.id,
            timelineStart: .zero,
            duration: RationalTime(value: 1, timescale: 1)
        )]
        project.timeline.tracks[1].clips = [TimelineClip(
            name: audioAsset.displayName,
            kind: .audio,
            assetID: audioAsset.id,
            timelineStart: .zero,
            duration: RationalTime(value: 1, timescale: 1)
        )]

        let access = MediaAccessManager()
        let rendered = try await AVCompositionBuilder(accessManager: access).build(project: project)
        let preferences = ExportPreferences(resolution: .p720, frameRate: .fps30, quality: .high)
        let plan = try ExportPlan(filename: "export", project: project, preferences: preferences)
        let result = try await AVExportService().export(
            rendered: rendered,
            plan: plan,
            destination: outputURL,
            progress: { _ in }
        )

        XCTAssertTrue(result.hasVideo)
        XCTAssertTrue(result.hasAudio)
        XCTAssertEqual(result.resolution, Resolution(width: 1280, height: 720))
        XCTAssertEqual(result.duration.seconds, 1, accuracy: 0.08)
        await access.releaseAll()
    }

    func testCancelledWaveformDoesNotPublishResult() async throws {
        let audioURL = temporaryDirectory.appendingPathComponent("long-audio.caf")
        try SyntheticMediaFactory.makeAudio(at: audioURL, seconds: 10)
        let generator = AVWaveformGenerator()
        let task = Task {
            try await generator.waveform(
                for: WaveformRequest(assetID: UUID(), sampleCount: 10_000),
                url: audioURL
            )
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}
