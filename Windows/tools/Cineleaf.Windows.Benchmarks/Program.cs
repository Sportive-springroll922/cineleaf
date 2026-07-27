using System.Diagnostics;
using System.Text.Json;
using Cineleaf.Core;

var large = LargeProject();
var indexed = IndexedTimeline();
var index = new TimelineIndex(indexed);
var visibleRange = new RationalTimeRange(new RationalTime(10_000, 1), new RationalTime(30, 1));

var results = new Dictionary<string, Measurement>
{
    ["validate_100_clips_10_tracks_ms"] = Measure(() => ProjectValidator.Validate(large)),
    ["encode_100_clips_ms"] = Measure(() => _ = ProjectCodec.Encode(large)),
    ["encode_decode_100_clips_ms"] = Measure(() => _ = ProjectCodec.Decode(ProjectCodec.Encode(large))),
    ["move_clip_100_clips_ms"] = Measure(() =>
    {
        var editor = new ProjectEditor(large);
        editor.Move(large.Timeline.Tracks[0].Clips[0].Id, RationalTime.Zero);
    }),
    ["visible_lookup_10000_clips_ms"] = Measure(() => _ = index.Visible(indexed.Tracks[0].Id, visibleRange))
};

Console.WriteLine(JsonSerializer.Serialize(new
{
    timestampUtc = DateTimeOffset.UtcNow,
    configuration = "Release",
    runtime = Environment.Version.ToString(),
    operatingSystem = Environment.OSVersion.VersionString,
    data = new { clips = 100, tracks = 10, durationSeconds = 3600, indexedClips = 10_000 },
    results
}, new JsonSerializerOptions { WriteIndented = true }));

static Measurement Measure(Action action)
{
    for (var index = 0; index < 10; index++) action();
    var samples = new double[50];
    for (var index = 0; index < samples.Length; index++)
    {
        var timer = Stopwatch.StartNew();
        action();
        timer.Stop();
        samples[index] = timer.Elapsed.TotalMilliseconds;
    }
    Array.Sort(samples);
    return new Measurement(samples[0], samples[samples.Length / 2], samples[^1]);
}

static CineleafProject LargeProject()
{
    var project = new CineleafProject { Name = "Performance" };
    project.Timeline.Tracks.Clear();
    for (var trackIndex = 0; trackIndex < 10; trackIndex++)
    {
        var track = new TimelineTrack { Name = $"V{trackIndex + 1}", Kind = TrackKind.Video };
        for (var clipIndex = 0; clipIndex < 10; clipIndex++)
            track.Clips.Add(new TimelineClip
            {
                Name = $"Title {trackIndex}-{clipIndex}", Kind = ClipKind.Text,
                TimelineStart = new RationalTime(clipIndex * 360, 1), Duration = new RationalTime(360, 1),
                TextStyle = new TextStyle { Text = "Cineleaf benchmark" }
            });
        project.Timeline.Tracks.Add(track);
    }
    return project;
}

static Timeline IndexedTimeline()
{
    var track = new TimelineTrack { Name = "V1", Kind = TrackKind.Video };
    for (var index = 0; index < 10_000; index++)
        track.Clips.Add(new TimelineClip
        {
            Name = $"Clip {index}", Kind = ClipKind.Text,
            TimelineStart = new RationalTime(index * 2, 1), Duration = new RationalTime(1, 1),
            TextStyle = new TextStyle { Text = index.ToString(System.Globalization.CultureInfo.InvariantCulture) }
        });
    return new Timeline { Tracks = [track] };
}

internal sealed record Measurement(double Minimum, double Median, double Maximum);
