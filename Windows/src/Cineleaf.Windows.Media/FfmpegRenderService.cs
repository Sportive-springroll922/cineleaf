using System.Globalization;
using Cineleaf.Core;

namespace Cineleaf.Media;

public sealed record RenderResult(string Path, RationalTime Duration, Resolution Resolution, bool HasAudio, string Encoder);

public sealed class FfmpegRenderService(
    FfmpegToolchain toolchain,
    EncoderProbeService encoderProbe,
    MediaInspector inspector)
{
    public async Task<RenderResult> RenderAsync(
        RenderRequest request,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var destination = Path.GetFullPath(request.Destination);
        var parent = Path.GetDirectoryName(destination) ?? throw new InvalidOperationException("The output folder is invalid.");
        Directory.CreateDirectory(parent);
        EnsureDiskSpace(parent);
        var encoder = await encoderProbe.SelectAsync(request.Codec, cancellationToken).ConfigureAwait(false);
        var workspace = Path.Combine(Path.GetTempPath(), "Cineleaf", "Render", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workspace);
        try
        {
            var plan = FfmpegCommandBuilder.Build(request with { Destination = destination }, encoder, workspace);
            foreach (var textFile in plan.TemporaryTextFiles)
                await File.WriteAllTextAsync(textFile.Path, textFile.Content, cancellationToken).ConfigureAwait(false);
            if (File.Exists(destination)) File.Delete(destination);
            await MediaProcessRunner.RunAsync(toolchain.FfmpegPath, plan.Arguments, line =>
            {
                if (line.StartsWith("out_time_us=", StringComparison.Ordinal) &&
                    long.TryParse(line.AsSpan(12), NumberStyles.Integer, CultureInfo.InvariantCulture, out var microseconds))
                {
                    var ratio = microseconds / 1_000_000d / Math.Max(plan.ExpectedDuration.TotalSeconds, 0.001);
                    progress?.Report(Math.Clamp(ratio, 0, 0.99));
                }
            }, cancellationToken).ConfigureAwait(false);
            var validated = await inspector.InspectOutputAsync(destination, cancellationToken).ConfigureAwait(false);
            if (validated.Resolution != request.Resolution)
                throw new InvalidDataException($"The export is {validated.Resolution.Width}×{validated.Resolution.Height}, not {request.Resolution.Width}×{request.Resolution.Height}.");
            progress?.Report(1);
            return new RenderResult(destination, validated.Duration, validated.Resolution, validated.HasAudio, encoder);
        }
        catch
        {
            if (File.Exists(destination)) File.Delete(destination);
            throw;
        }
        finally
        {
            if (Directory.Exists(workspace)) Directory.Delete(workspace, recursive: true);
        }
    }

    private static void EnsureDiskSpace(string directory)
    {
        var root = Path.GetPathRoot(Path.GetFullPath(directory));
        if (root is null) return;
        var drive = new DriveInfo(root);
        if (drive.AvailableFreeSpace < 256L * 1024 * 1024)
            throw new IOException("There is less than 256 MB of free space on the output drive.");
    }
}
