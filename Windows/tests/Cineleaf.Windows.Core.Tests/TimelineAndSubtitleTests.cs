using System.Diagnostics;
using System.Globalization;
using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class TimelineAndSubtitleTests
{
    private static readonly string[] ExpectedCaptions = ["Hello world.", "This continues"];

    [Fact]
    public void IndexReturnsOnlyVisibleClipsFromTenThousand()
    {
        var track = new TimelineTrack { Name = "V1", Kind = TrackKind.Video };
        for (var index = 0; index < 10_000; index++)
        {
            track.Clips.Add(new TimelineClip
            {
                Name = $"Clip {index}",
                Kind = ClipKind.Text,
                TimelineStart = new RationalTime(index * 2, 1),
                Duration = new RationalTime(1, 1),
                TextStyle = new TextStyle { Text = index.ToString(CultureInfo.InvariantCulture) }
            });
        }
        var timeline = new Timeline { Tracks = [track] };
        var stopwatch = Stopwatch.StartNew();
        var indexer = new TimelineIndex(timeline);
        var clips = indexer.Visible(track.Id, new RationalTimeRange(new RationalTime(10_000, 1), new RationalTime(10, 1)));
        stopwatch.Stop();

        Assert.Equal(5, clips.Count);
        Assert.True(stopwatch.Elapsed < TimeSpan.FromSeconds(1), $"Lookup took {stopwatch.Elapsed}");
    }

    [Fact]
    public void ParsesAndWritesSrtAndWebVtt()
    {
        const string srt = "1\n00:00:01,250 --> 00:00:03,500\nHello world\n\n";

        var cues = SubtitleCodec.Parse(srt, SubtitleFormat.Srt);
        var webVtt = SubtitleCodec.Serialize(cues, SubtitleFormat.WebVtt);

        Assert.Single(cues);
        Assert.Equal(1.25, cues[0].Start.Seconds, 3);
        Assert.StartsWith("WEBVTT", webVtt, StringComparison.Ordinal);
    }

    [Fact]
    public void CaptionBuilderSplitsReadablePhrases()
    {
        var tokens = new[]
        {
            new TranscriptToken("Hello", RationalTime.Zero, new RationalTime(1, 2)),
            new TranscriptToken("world.", new RationalTime(1, 2), new RationalTime(1, 2)),
            new TranscriptToken("This", new RationalTime(2, 1), new RationalTime(1, 2)),
            new TranscriptToken("continues", new RationalTime(5, 2), new RationalTime(1, 2))
        };

        var cues = AutomaticCaptionBuilder.Build(tokens, maximumCharacters: 20, maximumDurationSeconds: 3);

        Assert.Equal(ExpectedCaptions, cues.Select(cue => cue.Text));
    }
}
