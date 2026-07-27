using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace Cineleaf.Media;

public sealed class ThumbnailService(FfmpegToolchain toolchain, string cacheDirectory)
{
    public async Task<string> GenerateAsync(string mediaPath, TimeSpan time, int width, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(cacheDirectory);
        var identity = $"{Path.GetFullPath(mediaPath)}|{File.GetLastWriteTimeUtc(mediaPath).Ticks}|{time.TotalMilliseconds:0}|{width}";
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity))).ToLowerInvariant();
        var output = Path.Combine(cacheDirectory, $"{key}.jpg");
        if (File.Exists(output)) return output;
        var temporary = output + ".tmp.jpg";
        try
        {
            await MediaProcessRunner.RunAsync(toolchain.FfmpegPath,
            [
                "-hide_banner", "-loglevel", "error", "-y", "-ss", time.TotalSeconds.ToString("0.###", System.Globalization.CultureInfo.InvariantCulture),
                "-i", mediaPath, "-frames:v", "1", "-vf", $"scale={Math.Max(16, width)}:-2", "-q:v", "4", temporary
            ], cancellationToken: cancellationToken).ConfigureAwait(false);
            File.Move(temporary, output, overwrite: true);
            return output;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

public sealed class WaveformService(FfmpegToolchain toolchain)
{
    public async Task<IReadOnlyList<float>> GenerateAsync(string mediaPath, CancellationToken cancellationToken = default)
    {
        var info = MediaProcessRunner.CreateStartInfo(toolchain.FfmpegPath,
        [
            "-hide_banner", "-loglevel", "error", "-i", mediaPath, "-vn", "-ac", "1", "-ar", "8000", "-f", "f32le", "pipe:1"
        ]);
        using var process = new Process { StartInfo = info };
        if (!process.Start()) throw new InvalidOperationException("Could not start audio analysis.");
        using var registration = cancellationToken.Register(() =>
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
        });
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        var peaks = new List<float>();
        var buffer = new byte[4 * 800];
        while (await process.StandardOutput.BaseStream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false) is var count && count > 0)
        {
            var peak = 0f;
            for (var index = 0; index + 3 < count; index += 4)
                peak = Math.Max(peak, Math.Abs(BitConverter.ToSingle(buffer, index)));
            peaks.Add(Math.Clamp(peak, 0, 1));
        }
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        var error = await errorTask.ConfigureAwait(false);
        if (process.ExitCode != 0) throw new MediaProcessException(toolchain.FfmpegPath, process.ExitCode, error);
        return Downsample(peaks, 5_000);
    }

    private static IReadOnlyList<float> Downsample(List<float> values, int maximum)
    {
        if (values.Count <= maximum) return values;
        var result = new float[maximum];
        for (var bucket = 0; bucket < maximum; bucket++)
        {
            var start = (int)((long)bucket * values.Count / maximum);
            var end = Math.Max(start + 1, (int)((long)(bucket + 1) * values.Count / maximum));
            var peak = 0f;
            for (var index = start; index < end; index++) peak = Math.Max(peak, values[index]);
            result[bucket] = peak;
        }
        return result;
    }
}
