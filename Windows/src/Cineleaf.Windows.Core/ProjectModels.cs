using System.Text.Json.Serialization;

namespace Cineleaf.Core;

public enum CanvasPreset { Landscape16x9, Vertical9x16, Square1x1, Portrait4x5 }
public enum ProjectFrameRate { Fps24, Fps25, Fps30, Fps50, Fps60 }
public enum MediaKind { Video, Audio, Image }
public enum TrackKind { Video, Audio }
public enum ClipKind { Video, Audio, Image, Text }
public enum ContentMode { Fit, Fill, Crop }
public enum TextAlignment { Leading, Center, Trailing }
public enum TextAnimation { None, Fade, SlideUp }
public enum ClipRole { Standard, Subtitle, Voiceover }
public enum VideoEffectKind { GaussianBlur, Sharpen, Vignette, Monochrome, Sepia, Bloom }
public enum TransitionKind { CrossDissolve, FadeThroughBlack, SlideLeft, SlideRight, WipeLeft, Blur }
public enum KeyframedProperty { PositionX, PositionY, Scale, RotationDegrees, Opacity, Volume }
public enum ExportCodec { H264, Hevc }
public enum ExportContainer { Mp4, Mov }
public enum ExportQuality { Compact, Balanced, High }
public enum ExportResolutionPreset { P720, P1080, P1440, P2160 }
public enum SubtitleFormat { Srt, WebVtt }

public sealed record Resolution(int Width, int Height);

public sealed class MediaMetadata
{
    public RationalTime? Duration { get; set; }
    public Resolution? Resolution { get; set; }
    public RationalRate? FrameRate { get; set; }
    public string FileType { get; set; } = string.Empty;
    public bool HasAudio { get; set; }
    public long FileSize { get; set; }
}

public sealed class MediaReference
{
    public string LastKnownPath { get; set; } = string.Empty;
    public string? ProjectRelativePath { get; set; }
    public byte[]? SecurityScopedBookmark { get; set; }
    public DateTimeOffset? SourceModificationDate { get; set; }
}

public sealed class MediaAsset
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string DisplayName { get; set; } = string.Empty;
    public MediaKind Kind { get; set; }
    public MediaReference Reference { get; set; } = new();
    public MediaMetadata Metadata { get; set; } = new();
    public MediaReference? ProxyReference { get; set; }
}

public sealed class ClipTransform
{
    public double PositionX { get; set; }
    public double PositionY { get; set; }
    public double Scale { get; set; } = 1;
    public double RotationDegrees { get; set; }
    public double CropTop { get; set; }
    public double CropLeading { get; set; }
    public double CropBottom { get; set; }
    public double CropTrailing { get; set; }
    public ContentMode ContentMode { get; set; } = ContentMode.Fit;
}

public sealed class TextStyle
{
    public string Text { get; set; } = string.Empty;
    public string FontName { get; set; } = ".AppleSystemUIFont";
    public double FontSize { get; set; } = 64;
    public double FontWeight { get; set; }
    public TextAlignment Alignment { get; set; } = TextAlignment.Center;
    public string ForegroundHex { get; set; } = "#FFFFFFFF";
    public string BackgroundHex { get; set; } = "#00000000";
    public string StrokeHex { get; set; } = "#000000FF";
    public double StrokeWidth { get; set; }
    public double ShadowOpacity { get; set; }
    public TextAnimation Animation { get; set; }
}

public sealed class ClipFades
{
    public RationalTime VideoIn { get; set; } = RationalTime.Zero;
    public RationalTime VideoOut { get; set; } = RationalTime.Zero;
    public RationalTime AudioIn { get; set; } = RationalTime.Zero;
    public RationalTime AudioOut { get; set; } = RationalTime.Zero;
}

public sealed class ColorAdjustments
{
    public double Exposure { get; set; }
    public double Contrast { get; set; } = 1;
    public double Saturation { get; set; } = 1;
    public double Temperature { get; set; }
    public double Tint { get; set; }
    public double Highlights { get; set; }
    public double Shadows { get; set; }
    public double Sharpen { get; set; }
    public double Vignette { get; set; }
}

public sealed class VideoEffect
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public VideoEffectKind Kind { get; set; }
    public bool IsEnabled { get; set; } = true;
    public double Amount { get; set; } = 0.5;
}

public sealed class ClipTransition
{
    public TransitionKind Kind { get; set; }
    public RationalTime Duration { get; set; } = new(1, 2);
}

public readonly record struct ScalarKeyframe(RationalTime Time, double Value);

public sealed class ClipKeyframes
{
    public List<ScalarKeyframe> PositionX { get; set; } = [];
    public List<ScalarKeyframe> PositionY { get; set; } = [];
    public List<ScalarKeyframe> Scale { get; set; } = [];
    public List<ScalarKeyframe> RotationDegrees { get; set; } = [];
    public List<ScalarKeyframe> Opacity { get; set; } = [];
    public List<ScalarKeyframe> Volume { get; set; } = [];
}

public sealed class TimelineClip
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public ClipKind Kind { get; set; }
    [JsonPropertyName("assetID")] public Guid? AssetId { get; set; }
    public RationalTime TimelineStart { get; set; } = RationalTime.Zero;
    public RationalTime Duration { get; set; } = RationalTime.Zero;
    public RationalTime SourceStart { get; set; } = RationalTime.Zero;
    public ClipTransform Transform { get; set; } = new();
    public double Opacity { get; set; } = 1;
    public bool IsEnabled { get; set; } = true;
    public bool IsVideoMuted { get; set; }
    public double AudioVolume { get; set; } = 1;
    public ClipFades Fades { get; set; } = new();
    public TextStyle? TextStyle { get; set; }
    public double PlaybackRate { get; set; } = 1;
    public bool IsReversed { get; set; }
    [JsonPropertyName("groupID")] public Guid? GroupId { get; set; }
    [JsonPropertyName("linkGroupID")] public Guid? LinkGroupId { get; set; }
    public ClipRole Role { get; set; }
    public ColorAdjustments ColorAdjustments { get; set; } = new();
    public List<VideoEffect> Effects { get; set; } = [];
    public ClipTransition? TransitionIn { get; set; }
    public ClipTransition? TransitionOut { get; set; }
    public ClipKeyframes Keyframes { get; set; } = new();
    [JsonIgnore] public RationalTime TimelineEnd => TimelineStart + Duration;
}

public sealed class TimelineTrack
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public TrackKind Kind { get; set; }
    public bool IsMuted { get; set; }
    public bool IsLocked { get; set; }
    public List<TimelineClip> Clips { get; set; } = [];
}

public sealed class TimelineMarker
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public RationalTime Time { get; set; } = RationalTime.Zero;
    public string Name { get; set; } = "Marker";
    public string ColorHex { get; set; } = "#F7C948FF";
}

public sealed class Timeline
{
    public List<TimelineTrack> Tracks { get; set; } = [];
    public List<TimelineMarker> Markers { get; set; } = [];
    [JsonIgnore]
    public RationalTime Duration => Tracks.SelectMany(track => track.Clips)
        .Select(clip => clip.TimelineEnd).DefaultIfEmpty(RationalTime.Zero).Max();
}

public sealed class ExportPreferences
{
    public ExportResolutionPreset Resolution { get; set; } = ExportResolutionPreset.P1080;
    public ProjectFrameRate FrameRate { get; set; } = ProjectFrameRate.Fps30;
    public ExportQuality Quality { get; set; } = ExportQuality.Balanced;
    public ExportCodec Codec { get; set; } = ExportCodec.H264;
    public ExportContainer Container { get; set; } = ExportContainer.Mp4;
}

public sealed class CineleafProject
{
    public const int CurrentFormatVersion = 2;
    public int FormatVersion { get; set; } = CurrentFormatVersion;
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Untitled";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset ModifiedAt { get; set; } = DateTimeOffset.UtcNow;
    public Resolution Canvas { get; set; } = new(1920, 1080);
    public CanvasPreset CanvasPreset { get; set; } = CanvasPreset.Landscape16x9;
    public ProjectFrameRate FrameRate { get; set; } = ProjectFrameRate.Fps30;
    public List<MediaAsset> Assets { get; set; } = [];
    public Timeline Timeline { get; set; } = new()
    {
        Tracks =
        [
            new TimelineTrack { Name = "V1", Kind = TrackKind.Video },
            new TimelineTrack { Name = "A1", Kind = TrackKind.Audio }
        ]
    };
    public ExportPreferences ExportPreferences { get; set; } = new();
}

public sealed record SubtitleCue(Guid Id, RationalTime Start, RationalTime Duration, string Text)
{
    public SubtitleCue(RationalTime start, RationalTime duration, string text) : this(Guid.NewGuid(), start, duration, text) { }
}

public sealed record TranscriptToken(string Text, RationalTime Start, RationalTime Duration);
