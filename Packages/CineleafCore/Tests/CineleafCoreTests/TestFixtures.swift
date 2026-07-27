import Foundation
import CineleafCore

enum TestFixtures {
    static func asset(
        id: UUID = UUID(),
        kind: MediaKind = .video,
        duration: RationalTime = RationalTime(value: 10, timescale: 1),
        hasAudio: Bool = true
    ) -> MediaAsset {
        MediaAsset(
            id: id,
            displayName: "fixture.mov",
            kind: kind,
            reference: MediaReference(lastKnownPath: "/tmp/fixture.mov"),
            metadata: MediaMetadata(
                duration: duration,
                resolution: kind == .audio ? nil : Resolution(width: 1920, height: 1080),
                frameRate: kind == .audio ? nil : RationalRate(numerator: 30),
                fileType: kind == .audio ? "m4a" : "mov",
                hasAudio: hasAudio,
                fileSize: 1_024
            )
        )
    }

    static func projectWithClip(
        start: RationalTime = .zero,
        duration: RationalTime = RationalTime(value: 10, timescale: 1)
    ) -> (project: CineleafProject, asset: MediaAsset, clip: TimelineClip, videoTrackID: UUID) {
        let asset = asset(duration: duration)
        var project = CineleafProject(name: "Fixture")
        let trackID = project.timeline.tracks[0].id
        let clip = TimelineClip(
            name: asset.displayName,
            kind: .video,
            assetID: asset.id,
            timelineStart: start,
            duration: duration
        )
        project.assets = [asset]
        project.timeline.tracks[0].clips = [clip]
        return (project, asset, clip, trackID)
    }
}

