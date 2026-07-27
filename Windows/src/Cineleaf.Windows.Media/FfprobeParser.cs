using System.Globalization;
using System.Text.Json;
using Cineleaf.Core;

namespace Cineleaf.Media;

public static class FfprobeParser
{
    public static MediaMetadata Parse(string json, string extension)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var streams = root.TryGetProperty("streams", out var streamArray) ? streamArray : default;
        JsonElement? video = null;
        var hasAudio = false;
        if (streams.ValueKind == JsonValueKind.Array)
        {
            foreach (var stream in streams.EnumerateArray())
            {
                var type = stream.TryGetProperty("codec_type", out var codecType) ? codecType.GetString() : null;
                if (type == "video" && video is null) video = stream;
                if (type == "audio") hasAudio = true;
            }
        }
        var format = root.TryGetProperty("format", out var formatElement) ? formatElement : default;
        var duration = ReadDouble(format, "duration");
        var size = ReadLong(format, "size");
        Resolution? resolution = null;
        RationalRate? frameRate = null;
        if (video is { } videoStream)
        {
            var width = videoStream.TryGetProperty("width", out var widthElement) ? widthElement.GetInt32() : 0;
            var height = videoStream.TryGetProperty("height", out var heightElement) ? heightElement.GetInt32() : 0;
            if (width > 0 && height > 0) resolution = new Resolution(width, height);
            if (videoStream.TryGetProperty("avg_frame_rate", out var rateElement))
                frameRate = ParseRate(rateElement.GetString());
        }
        return new MediaMetadata
        {
            Duration = duration is > 0 ? RationalTime.FromSeconds(duration.Value) : null,
            Resolution = resolution,
            FrameRate = frameRate,
            FileType = extension.TrimStart('.').ToLowerInvariant(),
            HasAudio = hasAudio,
            FileSize = size ?? 0
        };
    }

    private static RationalRate? ParseRate(string? value)
    {
        var parts = value?.Split('/');
        if (parts?.Length != 2 || !int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var numerator) ||
            !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var denominator) || numerator <= 0 || denominator <= 0)
            return null;
        return new RationalRate(numerator, denominator);
    }

    private static double? ReadDouble(JsonElement element, string property) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out var value) &&
        double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) ? number : null;

    private static long? ReadLong(JsonElement element, string property) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out var value) &&
        long.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var number) ? number : null;
}
