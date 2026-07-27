using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class AudioInsightTests
{
    [Fact]
    public void SilenceDetectionRequiresMinimumDuration()
    {
        var peaks = new float[] { 0.2f, 0, 0, 0.2f, 0, 0, 0, 0.2f };

        var ranges = AudioInsights.DetectSilence(peaks, samplesPerSecond: 2, threshold: 0.01f, minimumSeconds: 1.2);

        Assert.Single(ranges);
        Assert.Equal(2, ranges[0].Start.Seconds, 3);
        Assert.Equal(1.5, ranges[0].Duration.Seconds, 3);
    }

    [Fact]
    public void BeatDetectionFindsSeparatedLocalPeaks()
    {
        var peaks = new float[] { 0.01f, 0.02f, 0.9f, 0.02f, 0.01f, 0.01f, 0.8f, 0.01f, 0.02f };

        var beats = AudioInsights.DetectBeats(peaks, samplesPerSecond: 4, minimumSpacingSeconds: 0.5);

        Assert.Equal(2, beats.Count);
        Assert.Equal(0.5, beats[0].Seconds, 3);
        Assert.Equal(1.5, beats[1].Seconds, 3);
    }

    [Fact]
    public void RemovingRangeSplitsClipAndClosesTimeline()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var editor = new ProjectEditor(project);

        editor.RemoveTimelineRanges([new RationalTimeRange(new RationalTime(3, 1), new RationalTime(2, 1))]);

        var clips = editor.Project.Timeline.Tracks[0].Clips;
        Assert.Equal(2, clips.Count);
        Assert.Equal(new RationalTime(3, 1), clips[0].Duration);
        Assert.Equal(new RationalTime(3, 1), clips[1].TimelineStart);
        Assert.Equal(new RationalTime(5, 1), clips[1].SourceStart);
        Assert.Equal(new RationalTime(8, 1), editor.Project.Timeline.Duration);
    }
}
