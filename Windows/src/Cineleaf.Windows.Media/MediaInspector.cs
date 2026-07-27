using Cineleaf.Core;

namespace Cineleaf.Media;

public sealed class MediaInspector(FfmpegToolchain toolchain)
{
    public async Task<MediaMetadata> InspectAsync(string path, CancellationToken cancellationToken = default)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("The media file no longer exists.", path);
        var result = await MediaProcessRunner.RunAsync(toolchain.FfprobePath,
        [
            "-v", "error", "-show_entries", "format=duration,format_name,size:stream=codec_type,width,height,avg_frame_rate",
            "-of", "json", path
        ], cancellationToken: cancellationToken).ConfigureAwait(false);
        var metadata = FfprobeParser.Parse(result.StandardOutput, Path.GetExtension(path));
        if (metadata.Duration is null && metadata.Resolution is null)
            throw new InvalidDataException("Cineleaf could not find a playable video, audio, or image stream in this file.");
        return metadata;
    }

    public async Task<(RationalTime Duration, Resolution Resolution, bool HasAudio)> InspectOutputAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        var metadata = await InspectAsync(path, cancellationToken).ConfigureAwait(false);
        if (metadata.Duration is not { } duration || metadata.Resolution is not { } resolution)
            throw new InvalidDataException("The exported file does not contain valid video.");
        return (duration, resolution, metadata.HasAudio);
    }
}
