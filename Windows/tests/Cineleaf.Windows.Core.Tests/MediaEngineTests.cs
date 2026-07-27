using Cineleaf.Core;
using Cineleaf.Media;

namespace Cineleaf.Windows.Core.Tests;

public sealed class MediaEngineTests
{
    private const string ProbeJson = """
    {
      "format": { "duration": "12.500000", "format_name": "mov,mp4", "size": "4096" },
      "streams": [
        { "codec_type": "video", "width": 1920, "height": 1080, "avg_frame_rate": "30000/1001" },
        { "codec_type": "audio" }
      ]
    }
    """;

    [Fact]
    public void ProbeParserReadsVideoAudioAndFractionalFrameRate()
    {
        var metadata = FfprobeParser.Parse(ProbeJson, ".mp4");

        Assert.Equal(12.5, metadata.Duration!.Value.Seconds, 3);
        Assert.Equal(new Resolution(1920, 1080), metadata.Resolution);
        Assert.Equal(new RationalRate(30_000, 1001), metadata.FrameRate);
        Assert.True(metadata.HasAudio);
        Assert.Equal(4096, metadata.FileSize);
    }

    [Fact]
    public void RenderPlanBuildsAComposedTimelineWithoutShellCommandStrings()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        project.Timeline.Tracks[0].Clips[0].Fades.VideoIn = new RationalTime(1, 2);
        project.Timeline.Tracks.Add(new TimelineTrack
        {
            Name = "Titles",
            Kind = TrackKind.Video,
            Clips = [new TimelineClip
        {
            Name = "Title", Kind = ClipKind.Text, TimelineStart = new RationalTime(2, 1),
            Duration = new RationalTime(3, 1), TextStyle = new TextStyle { Text = "Safe: title's text" }
        }]
        });
        var request = new RenderRequest(project, @"C:\Output Folder\movie.mp4", new Resolution(1280, 720), 30,
            ExportCodec.H264, ExportQuality.Balanced, Preview: false);

        var plan = FfmpegCommandBuilder.Build(request, "h264_mf", Path.GetTempPath());

        Assert.Contains(@"C:\Media\Sample.mp4", plan.Arguments);
        Assert.Contains("overlay", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("drawtext", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("fade=t=in", plan.FilterGraph, StringComparison.Ordinal);
        Assert.DoesNotContain("cmd.exe", plan.Arguments, StringComparer.OrdinalIgnoreCase);
        Assert.Single(plan.TemporaryTextFiles);
    }

    [Fact]
    public void RenderPlanIncludesSpeedReverseEffectsAndAudioMix()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var clip = project.Timeline.Tracks[0].Clips[0];
        clip.PlaybackRate = 2;
        clip.Duration = new RationalTime(5, 1);
        clip.IsReversed = true;
        clip.Effects.Add(new VideoEffect { Kind = VideoEffectKind.GaussianBlur, Amount = 0.4 });

        var plan = FfmpegCommandBuilder.Build(new RenderRequest(project, "out.mp4", new Resolution(1920, 1080), 30,
            ExportCodec.H264, ExportQuality.High, Preview: false), "libopenh264", Path.GetTempPath());

        Assert.Contains("reverse", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("setpts=(PTS-STARTPTS)/2", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("atempo=2", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("gblur", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("amix", plan.FilterGraph, StringComparison.Ordinal);
    }

    [Fact]
    public void RenderPlanAppliesClipEdgeTransitions()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var clip = project.Timeline.Tracks[0].Clips[0];
        clip.TransitionIn = new ClipTransition { Kind = TransitionKind.CrossDissolve, Duration = new RationalTime(1, 2) };
        clip.TransitionOut = new ClipTransition { Kind = TransitionKind.SlideLeft, Duration = new RationalTime(1, 1) };

        var plan = FfmpegCommandBuilder.Build(new RenderRequest(project, "out.mp4", new Resolution(1920, 1080), 30,
            ExportCodec.H264, ExportQuality.High, Preview: false), "libopenh264", Path.GetTempPath());

        Assert.Contains("fade=t=in:st=0:d=0.5:alpha=1", plan.FilterGraph, StringComparison.Ordinal);
        Assert.Contains("if(gt(t\\,9)", plan.FilterGraph, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("h264_nvenc")]
    [InlineData("h264_qsv")]
    [InlineData("h264_amf")]
    [InlineData("h264_mf")]
    [InlineData("libopenh264")]
    public void EncoderArgumentsUseKnownSafeEncoderNames(string encoder)
    {
        var arguments = EncoderArguments.For(encoder, ExportQuality.Balanced, new Resolution(1920, 1080), preview: false);

        Assert.Equal("-c:v", arguments[0]);
        Assert.Equal(encoder, arguments[1]);
        Assert.Contains("-pix_fmt", arguments);
    }
}
