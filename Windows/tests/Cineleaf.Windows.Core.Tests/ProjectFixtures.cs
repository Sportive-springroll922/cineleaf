using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

internal static class ProjectFixtures
{
    internal static CineleafProject SimpleProject(DateTimeOffset created)
    {
        var asset = new MediaAsset
        {
            DisplayName = "Sample.mp4",
            Kind = MediaKind.Video,
            Reference = new MediaReference { LastKnownPath = @"C:\Media\Sample.mp4" },
            Metadata = new MediaMetadata
            {
                Duration = new RationalTime(30, 1),
                Resolution = new Resolution(1920, 1080),
                FrameRate = new RationalRate(30, 1),
                FileType = "mp4",
                HasAudio = true,
                FileSize = 1024
            }
        };
        var clip = new TimelineClip
        {
            Name = "Sample",
            Kind = ClipKind.Video,
            AssetId = asset.Id,
            TimelineStart = RationalTime.Zero,
            Duration = new RationalTime(10, 1),
            SourceStart = RationalTime.Zero
        };
        return new CineleafProject
        {
            Name = "Test",
            CreatedAt = created,
            ModifiedAt = created,
            Assets = [asset],
            Timeline = new Timeline
            {
                Tracks =
                [
                    new TimelineTrack { Name = "V1", Kind = TrackKind.Video, Clips = [clip] },
                    new TimelineTrack { Name = "A1", Kind = TrackKind.Audio }
                ]
            }
        };
    }

    internal static CineleafProject ThreeClipProject()
    {
        var project = SimpleProject(DateTimeOffset.UtcNow);
        var template = project.Timeline.Tracks[0].Clips[0];
        project.Timeline.Tracks[0].Clips = Enumerable.Range(0, 3).Select(index => new TimelineClip
        {
            Name = $"Clip {index}",
            Kind = ClipKind.Video,
            AssetId = template.AssetId,
            TimelineStart = new RationalTime(index * 10, 1),
            Duration = new RationalTime(10, 1),
            SourceStart = new RationalTime(index * 10, 1)
        }).ToList();
        return project;
    }
}
