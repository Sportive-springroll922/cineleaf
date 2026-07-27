namespace Cineleaf.Media;

public sealed record FfmpegToolchain(string FfmpegPath, string FfprobePath)
{
    public static FfmpegToolchain Locate()
    {
        var candidates = new List<string>();
        var configured = Environment.GetEnvironmentVariable("CINELEAF_FFMPEG_DIR");
        if (!string.IsNullOrWhiteSpace(configured)) candidates.Add(configured);
        candidates.Add(Path.Combine(AppContext.BaseDirectory, "Tools"));
        foreach (var directory in candidates)
        {
            var ffmpeg = Path.Combine(directory, "ffmpeg.exe");
            var ffprobe = Path.Combine(directory, "ffprobe.exe");
            if (File.Exists(ffmpeg) && File.Exists(ffprobe)) return new FfmpegToolchain(ffmpeg, ffprobe);
        }
        throw new FileNotFoundException("Cineleaf's local video engine is missing. Reinstall Cineleaf from the official GitHub release.");
    }
}
