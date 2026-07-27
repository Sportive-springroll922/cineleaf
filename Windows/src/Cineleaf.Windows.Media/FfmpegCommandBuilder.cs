using System.Globalization;
using System.Text;
using Cineleaf.Core;

namespace Cineleaf.Media;

public sealed record RenderRequest(
    CineleafProject Project,
    string Destination,
    Resolution Resolution,
    int FramesPerSecond,
    ExportCodec Codec,
    ExportQuality Quality,
    bool Preview);

public sealed record TemporaryTextFile(string Path, string Content);

public sealed record FfmpegCommandPlan(
    IReadOnlyList<string> Arguments,
    string FilterGraph,
    IReadOnlyList<TemporaryTextFile> TemporaryTextFiles,
    TimeSpan ExpectedDuration);

public static class EncoderArguments
{
    private static readonly HashSet<string> Supported = new(StringComparer.Ordinal)
    {
        "h264_nvenc", "h264_qsv", "h264_amf", "h264_mf", "h264_d3d12va", "libopenh264",
        "hevc_nvenc", "hevc_qsv", "hevc_amf", "hevc_mf", "hevc_d3d12va", "libkvazaar"
    };

    public static IReadOnlyList<string> For(string encoder, ExportQuality quality, Resolution resolution, bool preview)
    {
        if (!Supported.Contains(encoder)) throw new ArgumentException("Unsupported encoder.", nameof(encoder));
        var pixels = (double)resolution.Width * resolution.Height;
        var baseline = quality switch { ExportQuality.Compact => 3_000_000d, ExportQuality.High => 14_000_000d, _ => 8_000_000d };
        var bitrate = preview ? 1_500_000d : baseline * Math.Max(0.25, pixels / (1920 * 1080d));
        return [
            "-c:v", encoder,
            "-b:v", ((long)bitrate).ToString(CultureInfo.InvariantCulture),
            "-pix_fmt", "yuv420p"
        ];
    }
}

public static class FfmpegCommandBuilder
{
    public static FfmpegCommandPlan Build(RenderRequest request, string encoder, string temporaryDirectory)
    {
        ProjectValidator.Validate(request.Project);
        if (request.Resolution.Width <= 0 || request.Resolution.Height <= 0 || request.FramesPerSecond <= 0)
            throw new ArgumentOutOfRangeException(nameof(request));
        var duration = request.Project.Timeline.Duration;
        if (duration <= RationalTime.Zero) throw new InvalidOperationException("The timeline is empty.");

        var enabledMediaClips = request.Project.Timeline.Tracks
            .SelectMany((track, trackIndex) => track.Clips.Select(clip => (Track: track, TrackIndex: trackIndex, Clip: clip)))
            .Where(item => item.Clip.IsEnabled && item.Clip.Kind != ClipKind.Text && item.Clip.AssetId is not null)
            .OrderBy(item => item.TrackIndex).ThenBy(item => item.Clip.TimelineStart).ToArray();
        var assets = request.Project.Assets.ToDictionary(asset => asset.Id);
        var usedAssets = enabledMediaClips.Select(item => item.Clip.AssetId!.Value).Distinct().ToArray();
        var inputByAsset = usedAssets.Select((assetId, index) => (assetId, index)).ToDictionary(item => item.assetId, item => item.index);
        var arguments = new List<string> { "-hide_banner", "-y", "-nostdin" };
        foreach (var assetId in usedAssets)
        {
            if (!assets.TryGetValue(assetId, out var asset)) throw new InvalidOperationException($"Missing media asset {assetId}.");
            if (asset.Kind == MediaKind.Image) { arguments.Add("-loop"); arguments.Add("1"); }
            arguments.Add("-i");
            arguments.Add(asset.Reference.LastKnownPath);
        }

        var graph = new StringBuilder();
        var invariant = CultureInfo.InvariantCulture;
        var canvas = request.Resolution;
        graph.Append("color=c=black:s=").Append(canvas.Width).Append('x').Append(canvas.Height)
            .Append(":r=").Append(request.FramesPerSecond).Append(":d=").Append(F(duration.Seconds)).AppendLine("[base];");

        var videoUseCounts = enabledMediaClips.Where(item => item.Clip.Kind is ClipKind.Video or ClipKind.Image && !item.Clip.IsVideoMuted)
            .GroupBy(item => item.Clip.AssetId!.Value).ToDictionary(group => group.Key, group => group.Count());
        var audioUseCounts = enabledMediaClips.Where(item => item.Clip.Kind is ClipKind.Video or ClipKind.Audio &&
                assets[item.Clip.AssetId!.Value].Metadata.HasAudio && !item.Track.IsMuted)
            .GroupBy(item => item.Clip.AssetId!.Value).ToDictionary(group => group.Key, group => group.Count());
        var videoSourceLabels = BuildSourceSplits(graph, inputByAsset, videoUseCounts, audio: false);
        var audioSourceLabels = BuildSourceSplits(graph, inputByAsset, audioUseCounts, audio: true);
        var videoUseOffsets = new Dictionary<Guid, int>();
        var audioUseOffsets = new Dictionary<Guid, int>();
        var overlays = new List<(TimelineClip Clip, string Label)>();
        var audioLabels = new List<string>();

        foreach (var item in enabledMediaClips)
        {
            var clip = item.Clip;
            var assetId = clip.AssetId!.Value;
            var asset = assets[assetId];
            if (clip.Kind is ClipKind.Video or ClipKind.Image && !clip.IsVideoMuted)
            {
                var source = TakeSource(videoSourceLabels, videoUseOffsets, assetId);
                var label = $"v{overlays.Count}";
                graph.Append('[').Append(source).Append(']');
                AppendVideoFilters(graph, clip, asset, canvas);
                graph.Append('[').Append(label).AppendLine("];");
                overlays.Add((clip, label));
            }
            if (clip.Kind is ClipKind.Video or ClipKind.Audio && asset.Metadata.HasAudio && !item.Track.IsMuted)
            {
                var source = TakeSource(audioSourceLabels, audioUseOffsets, assetId);
                var label = $"a{audioLabels.Count}";
                graph.Append('[').Append(source).Append(']');
                AppendAudioFilters(graph, clip);
                graph.Append('[').Append(label).AppendLine("];");
                audioLabels.Add(label);
            }
        }

        var composite = "base";
        for (var index = 0; index < overlays.Count; index++)
        {
            var overlay = overlays[index];
            var next = $"overlay{index}";
            var x = OverlayPosition(overlay.Clip, horizontal: true);
            var y = OverlayPosition(overlay.Clip, horizontal: false);
            graph.Append('[').Append(composite).Append("][").Append(overlay.Label).Append("]overlay=x=")
                .Append(x).Append(":y=").Append(y).Append(":eof_action=pass:shortest=0[").Append(next).AppendLine("];");
            composite = next;
        }

        var temporaryFiles = new List<TemporaryTextFile>();
        foreach (var clip in request.Project.Timeline.Tracks.SelectMany(track => track.Clips)
                     .Where(clip => clip.IsEnabled && clip.Kind == ClipKind.Text && clip.TextStyle is not null)
                     .OrderBy(clip => clip.TimelineStart))
        {
            var textFile = Path.Combine(temporaryDirectory, $"cineleaf-text-{clip.Id:N}.txt");
            temporaryFiles.Add(new TemporaryTextFile(textFile, clip.TextStyle!.Text));
            var next = $"text{temporaryFiles.Count}";
            graph.Append('[').Append(composite).Append("]drawtext=textfile='").Append(EscapeFilterPath(textFile))
                .Append("':fontfile='C\\:/Windows/Fonts/segoeui.ttf':fontsize=").Append(F(clip.TextStyle.FontSize * clip.Transform.Scale))
                .Append(":fontcolor=").Append(FfColor(clip.TextStyle.ForegroundHex))
                .Append(":borderw=").Append(F(clip.TextStyle.StrokeWidth)).Append(":bordercolor=").Append(FfColor(clip.TextStyle.StrokeHex))
                .Append(":shadowcolor=black@").Append(F(clip.TextStyle.ShadowOpacity)).Append(":shadowx=2:shadowy=2")
                .Append(":x=(w-text_w)/2+").Append(F(clip.Transform.PositionX))
                .Append(":y=(h-text_h)/2+").Append(F(clip.Transform.PositionY))
                .Append(":enable='between(t,").Append(F(clip.TimelineStart.Seconds)).Append(',').Append(F(clip.TimelineEnd.Seconds)).Append(")'[")
                .Append(next).AppendLine("];");
            composite = next;
        }
        graph.Append('[').Append(composite).Append("]format=yuv420p[vout];");
        if (audioLabels.Count == 0)
            graph.Append("anullsrc=r=48000:cl=stereo,atrim=duration=").Append(F(duration.Seconds)).Append("[aout]");
        else
        {
            foreach (var label in audioLabels) graph.Append('[').Append(label).Append(']');
            graph.Append("amix=inputs=").Append(audioLabels.Count).Append(":duration=longest:normalize=0,")
                .Append("atrim=duration=").Append(F(duration.Seconds)).Append("[aout]");
        }

        var filterGraph = graph.ToString();
        arguments.Add("-filter_complex"); arguments.Add(filterGraph);
        arguments.Add("-map"); arguments.Add("[vout]");
        arguments.Add("-map"); arguments.Add("[aout]");
        arguments.AddRange(EncoderArguments.For(encoder, request.Quality, request.Resolution, request.Preview));
        arguments.Add("-c:a"); arguments.Add("aac");
        arguments.Add("-b:a"); arguments.Add(request.Preview ? "128000" : "192000");
        arguments.Add("-movflags"); arguments.Add("+faststart");
        arguments.Add("-progress"); arguments.Add("pipe:1");
        arguments.Add("-nostats"); arguments.Add(request.Destination);
        return new FfmpegCommandPlan(arguments, filterGraph, temporaryFiles, TimeSpan.FromSeconds(duration.Seconds));

        string F(double value) => value.ToString("0.######", invariant);
    }

    private static Dictionary<Guid, string[]> BuildSourceSplits(
        StringBuilder graph,
        Dictionary<Guid, int> inputByAsset,
        Dictionary<Guid, int> useCounts,
        bool audio)
    {
        var result = new Dictionary<Guid, string[]>();
        foreach (var (assetId, count) in useCounts)
        {
            var labels = Enumerable.Range(0, count).Select(index => $"{(audio ? 'a' : 'v')}src{inputByAsset[assetId]}_{index}").ToArray();
            graph.Append('[').Append(inputByAsset[assetId]).Append(audio ? ":a]" : ":v]");
            graph.Append(count == 1 ? (audio ? "anull" : "null") : (audio ? $"asplit={count}" : $"split={count}"));
            foreach (var label in labels) graph.Append('[').Append(label).Append(']');
            graph.AppendLine(";");
            result[assetId] = labels;
        }
        return result;
    }

    private static string TakeSource(
        Dictionary<Guid, string[]> labels,
        Dictionary<Guid, int> offsets,
        Guid assetId)
    {
        var offset = offsets.TryGetValue(assetId, out var current) ? current : 0;
        offsets[assetId] = offset + 1;
        return labels[assetId][offset];
    }

    private static void AppendVideoFilters(StringBuilder graph, TimelineClip clip, MediaAsset asset, Resolution canvas)
    {
        var sourceDuration = clip.Kind == ClipKind.Image ? clip.Duration.Seconds : clip.Duration.Seconds * clip.PlaybackRate;
        graph.Append("trim=start=").Append(F(clip.SourceStart.Seconds)).Append(":duration=").Append(F(sourceDuration)).Append(',');
        graph.Append("setpts=PTS-STARTPTS,");
        if (clip.IsReversed) graph.Append("reverse,");
        if (Math.Abs(clip.PlaybackRate - 1) > 0.000001) graph.Append("setpts=(PTS-STARTPTS)/").Append(F(clip.PlaybackRate)).Append(',');
        if (clip.Transform.CropTop > 0 || clip.Transform.CropLeading > 0 || clip.Transform.CropBottom > 0 || clip.Transform.CropTrailing > 0)
        {
            graph.Append("crop=iw*").Append(F(1 - clip.Transform.CropLeading - clip.Transform.CropTrailing))
                .Append(":ih*").Append(F(1 - clip.Transform.CropTop - clip.Transform.CropBottom))
                .Append(":iw*").Append(F(clip.Transform.CropLeading)).Append(":ih*").Append(F(clip.Transform.CropTop)).Append(',');
        }
        var width = Math.Max(2, (int)Math.Round(canvas.Width * clip.Transform.Scale / 2) * 2);
        var height = Math.Max(2, (int)Math.Round(canvas.Height * clip.Transform.Scale / 2) * 2);
        if (clip.Transform.ContentMode == ContentMode.Fit)
            graph.Append("scale=").Append(width).Append(':').Append(height).Append(":force_original_aspect_ratio=decrease,");
        else
            graph.Append("scale=").Append(width).Append(':').Append(height).Append(":force_original_aspect_ratio=increase,crop=")
                .Append(width).Append(':').Append(height).Append(',');
        if (Math.Abs(clip.Transform.RotationDegrees) > 0.000001)
            graph.Append("rotate=").Append(F(clip.Transform.RotationDegrees)).Append("*PI/180:ow=rotw(iw):oh=roth(ih):c=none,");
        AppendColorFilters(graph, clip);
        graph.Append("format=rgba,colorchannelmixer=aa=").Append(F(clip.Opacity)).Append(',');
        var fadeIn = Math.Max(clip.Fades.VideoIn.Seconds, IsSlide(clip.TransitionIn) ? 0 : clip.TransitionIn?.Duration.Seconds ?? 0);
        var fadeOut = Math.Max(clip.Fades.VideoOut.Seconds, IsSlide(clip.TransitionOut) ? 0 : clip.TransitionOut?.Duration.Seconds ?? 0);
        if (fadeIn > 0)
            graph.Append("fade=t=in:st=0:d=").Append(F(fadeIn)).Append(":alpha=1,");
        if (fadeOut > 0)
            graph.Append("fade=t=out:st=").Append(F(clip.Duration.Seconds - fadeOut)).Append(":d=")
                .Append(F(fadeOut)).Append(":alpha=1,");
        graph.Append("setpts=PTS+").Append(F(clip.TimelineStart.Seconds)).Append("/TB");

        static string F(double value) => value.ToString("0.######", CultureInfo.InvariantCulture);
        static bool IsSlide(ClipTransition? transition) => transition?.Kind is TransitionKind.SlideLeft or TransitionKind.SlideRight;
    }

    private static void AppendColorFilters(StringBuilder graph, TimelineClip clip)
    {
        var color = clip.ColorAdjustments;
        if (Math.Abs(color.Exposure) > 0.000001 || Math.Abs(color.Contrast - 1) > 0.000001 || Math.Abs(color.Saturation - 1) > 0.000001)
            graph.Append("eq=brightness=").Append(F(color.Exposure / 4)).Append(":contrast=").Append(F(color.Contrast))
                .Append(":saturation=").Append(F(color.Saturation)).Append(',');
        if (Math.Abs(color.Temperature) > 0.000001 || Math.Abs(color.Tint) > 0.000001)
            graph.Append("colorbalance=rs=").Append(F(color.Temperature * 0.2)).Append(":bs=").Append(F(-color.Temperature * 0.2))
                .Append(":gs=").Append(F(color.Tint * 0.15)).Append(',');
        if (Math.Abs(color.Highlights) > 0.000001 || Math.Abs(color.Shadows) > 0.000001)
            graph.Append("eq=gamma=").Append(F(1 + color.Shadows * 0.25 - color.Highlights * 0.15)).Append(',');
        if (color.Sharpen > 0) graph.Append("unsharp=5:5:").Append(F(color.Sharpen * 1.5)).Append(',');
        if (color.Vignette > 0) graph.Append("vignette=angle=").Append(F(Math.PI / 2 * color.Vignette)).Append(',');
        foreach (var effect in clip.Effects.Where(effect => effect.IsEnabled))
        {
            switch (effect.Kind)
            {
                case VideoEffectKind.GaussianBlur: graph.Append("gblur=sigma=").Append(F(effect.Amount * 12)).Append(','); break;
                case VideoEffectKind.Sharpen: graph.Append("unsharp=5:5:").Append(F(effect.Amount * 2)).Append(','); break;
                case VideoEffectKind.Vignette: graph.Append("vignette=angle=").Append(F(Math.PI / 2 * effect.Amount)).Append(','); break;
                case VideoEffectKind.Monochrome: graph.Append("hue=s=0,"); break;
                case VideoEffectKind.Sepia: graph.Append("colorchannelmixer=.393:.769:.189:.349:.686:.168:.272:.534:.131,"); break;
                case VideoEffectKind.Bloom: graph.Append("gblur=sigma=").Append(F(effect.Amount * 4)).Append(','); break;
            }
        }
        static string F(double value) => value.ToString("0.######", CultureInfo.InvariantCulture);
    }

    private static void AppendAudioFilters(StringBuilder graph, TimelineClip clip)
    {
        var sourceDuration = clip.Duration.Seconds * clip.PlaybackRate;
        graph.Append("atrim=start=").Append(F(clip.SourceStart.Seconds)).Append(":duration=").Append(F(sourceDuration))
            .Append(",asetpts=PTS-STARTPTS,");
        if (clip.IsReversed) graph.Append("areverse,");
        if (Math.Abs(clip.PlaybackRate - 1) > 0.000001) graph.Append("atempo=").Append(F(clip.PlaybackRate)).Append(',');
        graph.Append("volume=").Append(F(clip.AudioVolume)).Append(',');
        if (clip.Fades.AudioIn > RationalTime.Zero)
            graph.Append("afade=t=in:st=0:d=").Append(F(clip.Fades.AudioIn.Seconds)).Append(',');
        if (clip.Fades.AudioOut > RationalTime.Zero)
            graph.Append("afade=t=out:st=").Append(F(clip.Duration.Seconds - clip.Fades.AudioOut.Seconds)).Append(":d=")
                .Append(F(clip.Fades.AudioOut.Seconds)).Append(',');
        var delay = Math.Max(0, (long)Math.Round(clip.TimelineStart.Seconds * 1000));
        graph.Append("adelay=").Append(delay).Append('|').Append(delay);
        static string F(double value) => value.ToString("0.######", CultureInfo.InvariantCulture);
    }

    private static string EscapeFilterPath(string path) => path.Replace("\\", "/", StringComparison.Ordinal).Replace(":", "\\:", StringComparison.Ordinal).Replace("'", "'\\''", StringComparison.Ordinal);

    private static string OverlayPosition(TimelineClip clip, bool horizontal)
    {
        var offset = horizontal ? clip.Transform.PositionX : clip.Transform.PositionY;
        var expression = $"{(horizontal ? "(W-w)/2" : "(H-h)/2")}+{offset.ToString("0.######", CultureInfo.InvariantCulture)}";
        if (!horizontal) return expression;
        if (clip.TransitionIn is { Kind: TransitionKind.SlideLeft or TransitionKind.SlideRight } transitionIn)
        {
            var sign = transitionIn.Kind == TransitionKind.SlideLeft ? 1 : -1;
            var start = clip.TimelineStart.Seconds;
            var end = start + transitionIn.Duration.Seconds;
            expression += $"+if(lt(t\\,{F(end)})\\,{sign}*W*({F(end)}-t)/{F(transitionIn.Duration.Seconds)}\\,0)";
        }
        if (clip.TransitionOut is { Kind: TransitionKind.SlideLeft or TransitionKind.SlideRight } transitionOut)
        {
            var sign = transitionOut.Kind == TransitionKind.SlideLeft ? -1 : 1;
            var start = clip.TimelineEnd.Seconds - transitionOut.Duration.Seconds;
            expression += $"+if(gt(t\\,{F(start)})\\,{sign}*W*(t-{F(start)})/{F(transitionOut.Duration.Seconds)}\\,0)";
        }
        return expression;
        static string F(double value) => value.ToString("0.######", CultureInfo.InvariantCulture);
    }

    private static string FfColor(string hex)
    {
        var value = hex.TrimStart('#');
        if (value.Length < 6) return "white";
        var rgb = value[..6];
        var alpha = value.Length >= 8 && byte.TryParse(value.AsSpan(6, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var parsed)
            ? parsed / 255d : 1;
        return $"0x{rgb}@{alpha.ToString("0.###", CultureInfo.InvariantCulture)}";
    }
}
