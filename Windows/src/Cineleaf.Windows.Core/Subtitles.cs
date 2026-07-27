using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Cineleaf.Core;

public static partial class SubtitleCodec
{
    public static IReadOnlyList<SubtitleCue> Parse(string content, SubtitleFormat format)
    {
        ArgumentNullException.ThrowIfNull(content);
        var normalized = content.Replace("\r\n", "\n", StringComparison.Ordinal).Trim();
        if (format == SubtitleFormat.WebVtt && normalized.StartsWith("WEBVTT", StringComparison.OrdinalIgnoreCase))
            normalized = normalized[6..].TrimStart();
        var cues = new List<SubtitleCue>();
        foreach (var block in BlankLineRegex().Split(normalized))
        {
            var lines = block.Split('\n');
            var timingIndex = Array.FindIndex(lines, line => line.Contains("-->", StringComparison.Ordinal));
            if (timingIndex < 0) continue;
            var timing = lines[timingIndex].Split("-->", StringSplitOptions.TrimEntries);
            if (timing.Length != 2 || !TryParseTime(timing[0], out var start) || !TryParseTime(timing[1], out var end) || end <= start)
                throw new FormatException("A subtitle cue contains invalid timing.");
            var text = string.Join("\n", lines.Skip(timingIndex + 1)).Trim();
            if (text.Length > 0) cues.Add(new SubtitleCue(start, end - start, text));
        }
        return cues.OrderBy(cue => cue.Start).ToArray();
    }

    public static string Serialize(IEnumerable<SubtitleCue> cues, SubtitleFormat format)
    {
        var builder = new StringBuilder();
        if (format == SubtitleFormat.WebVtt) builder.AppendLine("WEBVTT").AppendLine();
        var index = 1;
        foreach (var cue in cues.OrderBy(item => item.Start))
        {
            if (format == SubtitleFormat.Srt) builder.AppendLine(index++.ToString(CultureInfo.InvariantCulture));
            builder.Append(FormatTime(cue.Start, format)).Append(" --> ").AppendLine(FormatTime(cue.Start + cue.Duration, format));
            builder.AppendLine(cue.Text).AppendLine();
        }
        return builder.ToString();
    }

    private static bool TryParseTime(string value, out RationalTime time)
    {
        var cleaned = value.Trim().Replace(',', '.');
        var parts = cleaned.Split(':');
        if (parts.Length is < 2 or > 3 || !double.TryParse(parts[^1], NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var seconds))
        {
            time = default;
            return false;
        }
        var hours = parts.Length == 3 && int.TryParse(parts[0], CultureInfo.InvariantCulture, out var parsedHours) ? parsedHours : 0;
        var minuteIndex = parts.Length - 2;
        if (!int.TryParse(parts[minuteIndex], CultureInfo.InvariantCulture, out var minutes))
        {
            time = default;
            return false;
        }
        time = RationalTime.FromSeconds(hours * 3600 + minutes * 60 + seconds, 1000);
        return true;
    }

    private static string FormatTime(RationalTime time, SubtitleFormat format)
    {
        var totalMilliseconds = Math.Max(0, (long)Math.Round(time.Seconds * 1000));
        var hours = totalMilliseconds / 3_600_000;
        var minutes = totalMilliseconds / 60_000 % 60;
        var seconds = totalMilliseconds / 1000 % 60;
        var milliseconds = totalMilliseconds % 1000;
        var separator = format == SubtitleFormat.Srt ? ',' : '.';
        return $"{hours:00}:{minutes:00}:{seconds:00}{separator}{milliseconds:000}";
    }

    [GeneratedRegex(@"\n\s*\n", RegexOptions.CultureInvariant)]
    private static partial Regex BlankLineRegex();
}

public static class AutomaticCaptionBuilder
{
    public static IReadOnlyList<SubtitleCue> Build(
        IEnumerable<TranscriptToken> tokens,
        int maximumCharacters = 42,
        double maximumDurationSeconds = 4)
    {
        var ordered = tokens.Where(token => !string.IsNullOrWhiteSpace(token.Text)).OrderBy(token => token.Start).ToArray();
        var cues = new List<SubtitleCue>();
        var words = new List<TranscriptToken>();
        foreach (var token in ordered)
        {
            var candidateLength = words.Sum(word => word.Text.Length) + words.Count + token.Text.Length;
            var candidateDuration = words.Count == 0 ? token.Duration.Seconds : (token.Start + token.Duration - words[0].Start).Seconds;
            if (words.Count > 0 && (candidateLength > maximumCharacters || candidateDuration > maximumDurationSeconds))
                Flush(words, cues);
            words.Add(token);
            if (token.Text.EndsWith('.') || token.Text.EndsWith('!') || token.Text.EndsWith('?')) Flush(words, cues);
        }
        Flush(words, cues);
        return cues;
    }

    private static void Flush(List<TranscriptToken> words, List<SubtitleCue> cues)
    {
        if (words.Count == 0) return;
        var start = words[0].Start;
        var end = words[^1].Start + words[^1].Duration;
        cues.Add(new SubtitleCue(start, end - start, string.Join(' ', words.Select(word => word.Text.Trim()))));
        words.Clear();
    }
}
