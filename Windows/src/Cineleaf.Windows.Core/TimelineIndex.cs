namespace Cineleaf.Core;

public sealed class TimelineIndex
{
    private readonly Dictionary<Guid, TimelineClip[]> _clipsByTrack;

    public TimelineIndex(Timeline timeline)
    {
        _clipsByTrack = timeline.Tracks.ToDictionary(
            track => track.Id,
            track => track.Clips.OrderBy(clip => clip.TimelineStart).ToArray());
    }

    public IReadOnlyList<TimelineClip> Visible(Guid trackId, RationalTimeRange range)
    {
        if (!_clipsByTrack.TryGetValue(trackId, out var clips) || clips.Length == 0) return [];
        var low = 0;
        var high = clips.Length;
        while (low < high)
        {
            var middle = low + (high - low) / 2;
            if (clips[middle].TimelineStart < range.Start) low = middle + 1;
            else high = middle;
        }
        var index = Math.Max(0, low - 1);
        var visible = new List<TimelineClip>();
        for (; index < clips.Length && clips[index].TimelineStart < range.End; index++)
        {
            if (new RationalTimeRange(clips[index].TimelineStart, clips[index].Duration).Intersects(range))
                visible.Add(clips[index]);
        }
        return visible;
    }
}
