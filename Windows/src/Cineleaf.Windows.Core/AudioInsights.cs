namespace Cineleaf.Core;

public static class AudioInsights
{
    public static IReadOnlyList<RationalTimeRange> DetectSilence(
        IReadOnlyList<float> peaks,
        double samplesPerSecond,
        float threshold = 0.025f,
        double minimumSeconds = 0.6)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(samplesPerSecond);
        var minimumSamples = Math.Max(1, (int)Math.Ceiling(minimumSeconds * samplesPerSecond));
        var ranges = new List<RationalTimeRange>();
        var start = -1;
        for (var index = 0; index <= peaks.Count; index++)
        {
            var silent = index < peaks.Count && peaks[index] <= threshold;
            if (silent && start < 0) start = index;
            if ((!silent || index == peaks.Count) && start >= 0)
            {
                if (index - start >= minimumSamples)
                    ranges.Add(new RationalTimeRange(RationalTime.FromSeconds(start / samplesPerSecond),
                        RationalTime.FromSeconds((index - start) / samplesPerSecond)));
                start = -1;
            }
        }
        return ranges;
    }

    public static IReadOnlyList<RationalTime> DetectBeats(
        IReadOnlyList<float> peaks,
        double samplesPerSecond,
        double minimumSpacingSeconds = 0.25)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(samplesPerSecond);
        var spacing = Math.Max(1, (int)Math.Ceiling(minimumSpacingSeconds * samplesPerSecond));
        var beats = new List<RationalTime>();
        var last = -spacing;
        for (var index = 2; index < peaks.Count - 2; index++)
        {
            var localAverage = (peaks[index - 2] + peaks[index - 1] + peaks[index + 1] + peaks[index + 2]) / 4;
            if (peaks[index] < Math.Max(0.08f, localAverage * 1.75f) || index - last < spacing) continue;
            beats.Add(RationalTime.FromSeconds(index / samplesPerSecond));
            last = index;
        }
        return beats;
    }
}
