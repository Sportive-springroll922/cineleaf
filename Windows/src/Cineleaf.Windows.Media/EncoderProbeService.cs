using Cineleaf.Core;

namespace Cineleaf.Media;

public sealed class EncoderProbeService(FfmpegToolchain toolchain) : IDisposable
{
    private readonly Dictionary<ExportCodec, string> _cache = [];
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<string> SelectAsync(ExportCodec codec, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_cache.TryGetValue(codec, out var cached)) return cached;
            var candidates = codec == ExportCodec.H264
                ? new[] { "h264_nvenc", "h264_qsv", "h264_amf", "h264_mf", "h264_d3d12va", "libopenh264" }
                : new[] { "hevc_nvenc", "hevc_qsv", "hevc_amf", "hevc_mf", "hevc_d3d12va", "libkvazaar" };
            foreach (var encoder in candidates)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (await WorksAsync(encoder, cancellationToken).ConfigureAwait(false))
                {
                    _cache[codec] = encoder;
                    return encoder;
                }
            }
            throw new InvalidOperationException($"No working {codec} encoder is available on this computer.");
        }
        finally { _gate.Release(); }
    }

    private async Task<bool> WorksAsync(string encoder, CancellationToken cancellationToken)
    {
        var output = Path.Combine(Path.GetTempPath(), $"cineleaf-encoder-{Guid.NewGuid():N}.mp4");
        try
        {
            await MediaProcessRunner.RunAsync(toolchain.FfmpegPath,
            [
                "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "color=black:s=64x64:d=0.1",
                "-frames:v", "1", "-c:v", encoder, "-pix_fmt", "yuv420p", output
            ], cancellationToken: cancellationToken).ConfigureAwait(false);
            return File.Exists(output) && new FileInfo(output).Length > 0;
        }
        catch (MediaProcessException) { return false; }
        finally { if (File.Exists(output)) File.Delete(output); }
    }

    public void Dispose() => _gate.Dispose();
}
