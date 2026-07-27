using System.Security.Cryptography;
using System.Text;
using Cineleaf.Core;

namespace Cineleaf.Media;

public sealed class PreviewCacheService(FfmpegRenderService renderer, string cacheDirectory)
{
    private const long MaximumBytes = 2L * 1024 * 1024 * 1024;

    public async Task<string> GetOrRenderAsync(
        CineleafProject project,
        Resolution resolution,
        int framesPerSecond,
        CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(cacheDirectory);
        var identity = new StringBuilder(ProjectCodec.Encode(project));
        foreach (var asset in project.Assets)
        {
            var path = asset.Reference.LastKnownPath;
            identity.Append('|').Append(path);
            if (File.Exists(path)) identity.Append('|').Append(File.GetLastWriteTimeUtc(path).Ticks).Append('|').Append(new FileInfo(path).Length);
        }
        identity.Append('|').Append(resolution.Width).Append('x').Append(resolution.Height).Append('|').Append(framesPerSecond);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity.ToString()))).ToLowerInvariant();
        var destination = Path.Combine(cacheDirectory, $"{hash}.mp4");
        if (File.Exists(destination))
        {
            File.SetLastAccessTimeUtc(destination, DateTime.UtcNow);
            return destination;
        }
        await renderer.RenderAsync(new RenderRequest(project, destination, resolution, framesPerSecond,
            ExportCodec.H264, ExportQuality.Compact, Preview: true), cancellationToken: cancellationToken).ConfigureAwait(false);
        TrimCache();
        return destination;
    }

    public long SizeBytes => Directory.Exists(cacheDirectory)
        ? Directory.EnumerateFiles(cacheDirectory, "*.mp4").Sum(path => new FileInfo(path).Length) : 0;

    public void Clear()
    {
        if (!Directory.Exists(cacheDirectory)) return;
        foreach (var file in Directory.EnumerateFiles(cacheDirectory, "*.mp4")) File.Delete(file);
    }

    private void TrimCache()
    {
        var files = Directory.EnumerateFiles(cacheDirectory, "*.mp4")
            .Select(path => new FileInfo(path)).OrderByDescending(file => file.LastAccessTimeUtc).ToArray();
        long total = 0;
        foreach (var file in files)
        {
            total += file.Length;
            if (total > MaximumBytes) file.Delete();
        }
    }
}
