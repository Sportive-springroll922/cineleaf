namespace Cineleaf.Core;

public sealed class InvalidEditException(string message, Exception? innerException = null) : Exception(message, innerException);

public sealed class ProjectEditor
{
    private const int HistoryLimit = 100;
    private readonly Stack<CineleafProject> _undo = new();
    private readonly Stack<CineleafProject> _redo = new();

    public ProjectEditor(CineleafProject project)
    {
        ProjectValidator.Validate(project);
        Project = ProjectCodec.Clone(project);
    }

    public CineleafProject Project { get; private set; }
    public bool CanUndo => _undo.Count > 0;
    public bool CanRedo => _redo.Count > 0;

    public Guid Split(Guid clipId, RationalTime playhead)
    {
        var rightId = Guid.NewGuid();
        Commit(candidate =>
        {
            var (track, clip) = Find(candidate, clipId);
            if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
            if (playhead <= clip.TimelineStart || playhead >= clip.TimelineEnd)
                throw new InvalidEditException("The playhead must be inside the clip.");
            var leftDuration = playhead - clip.TimelineStart;
            var right = ProjectCodec.Clone(candidate).Timeline.Tracks
                .SelectMany(item => item.Clips).First(item => item.Id == clipId);
            right.Id = rightId;
            right.TimelineStart = playhead;
            right.Duration = clip.Duration - leftDuration;
            right.SourceStart = clip.SourceStart + Scale(leftDuration, clip.PlaybackRate);
            clip.Duration = leftDuration;
            track.Clips.Add(right);
        });
        return rightId;
    }

    public void Move(Guid clipId, RationalTime start) => Commit(candidate =>
    {
        var (track, clip) = Find(candidate, clipId);
        if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
        if (start < RationalTime.Zero) throw new InvalidEditException("A clip cannot start before the timeline.");
        clip.TimelineStart = start;
    });

    public void Trim(Guid clipId, RationalTime newSourceStart, RationalTime newDuration) => Commit(candidate =>
    {
        var (track, clip) = Find(candidate, clipId);
        if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
        if (newSourceStart < RationalTime.Zero || newDuration <= RationalTime.Zero)
            throw new InvalidEditException("Trim values must be positive.");
        clip.SourceStart = newSourceStart;
        clip.Duration = newDuration;
    });

    public void Delete(IEnumerable<Guid> clipIds, bool ripple)
    {
        var selected = clipIds.ToHashSet();
        if (selected.Count == 0) return;
        Commit(candidate =>
        {
            foreach (var track in candidate.Timeline.Tracks)
            {
                var removed = track.Clips.Where(clip => selected.Contains(clip.Id)).OrderBy(clip => clip.TimelineStart).ToList();
                if (removed.Count == 0) continue;
                if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
                track.Clips.RemoveAll(clip => selected.Contains(clip.Id));
                if (!ripple) continue;
                foreach (var clip in track.Clips)
                {
                    var shift = removed.Where(item => item.TimelineEnd <= clip.TimelineStart)
                        .Aggregate(RationalTime.Zero, (total, item) => total + item.Duration);
                    clip.TimelineStart -= shift;
                }
            }
        });
    }

    public Guid Duplicate(Guid clipId)
    {
        var duplicateId = Guid.NewGuid();
        Commit(candidate =>
        {
            var (track, clip) = Find(candidate, clipId);
            if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
            var duplicate = ProjectCodec.Clone(candidate).Timeline.Tracks.SelectMany(item => item.Clips).First(item => item.Id == clipId);
            duplicate.Id = duplicateId;
            duplicate.TimelineStart = clip.TimelineEnd;
            duplicate.GroupId = null;
            duplicate.LinkGroupId = null;
            track.Clips.Add(duplicate);
        });
        return duplicateId;
    }

    public void AddClip(TimelineClip clip, Guid trackId) => Commit(candidate =>
    {
        var track = candidate.Timeline.Tracks.FirstOrDefault(item => item.Id == trackId)
            ?? throw new InvalidEditException("The target track no longer exists.");
        if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
        track.Clips.Add(clip);
    });

    public void AddAsset(MediaAsset asset) => Commit(candidate =>
    {
        if (candidate.Assets.Any(item => item.Id == asset.Id)) throw new InvalidEditException("That media item is already in the project.");
        candidate.Assets.Add(asset);
    });

    public Guid AddTrack(TrackKind kind, string? name = null)
    {
        var id = Guid.NewGuid();
        Commit(candidate => candidate.Timeline.Tracks.Add(new TimelineTrack
        {
            Id = id,
            Kind = kind,
            Name = name ?? $"{(kind == TrackKind.Video ? 'V' : 'A')}{candidate.Timeline.Tracks.Count(track => track.Kind == kind) + 1}"
        }));
        return id;
    }

    public Guid AddMarker(RationalTime time, string? name = null)
    {
        if (time < RationalTime.Zero) throw new InvalidEditException("A marker cannot be placed before the timeline.");
        var id = Guid.NewGuid();
        Commit(candidate => candidate.Timeline.Markers.Add(new TimelineMarker
        {
            Id = id,
            Time = time,
            Name = name ?? $"Marker {candidate.Timeline.Markers.Count + 1}"
        }));
        return id;
    }

    public IReadOnlyList<Guid> AddMarkers(IEnumerable<RationalTime> times, string prefix)
    {
        var ordered = times.Where(time => time >= RationalTime.Zero).Distinct().OrderBy(time => time).ToArray();
        var ids = ordered.Select(_ => Guid.NewGuid()).ToArray();
        Commit(candidate =>
        {
            for (var index = 0; index < ordered.Length; index++)
                candidate.Timeline.Markers.Add(new TimelineMarker { Id = ids[index], Time = ordered[index], Name = $"{prefix} {index + 1}" });
            candidate.Timeline.Markers = candidate.Timeline.Markers.OrderBy(marker => marker.Time).ToList();
        });
        return ids;
    }

    public void RemoveTimelineRanges(IEnumerable<RationalTimeRange> ranges)
    {
        var normalized = MergeRanges(ranges).OrderByDescending(range => range.Start).ToArray();
        if (normalized.Length == 0) return;
        Commit(candidate =>
        {
            foreach (var range in normalized)
                foreach (var track in candidate.Timeline.Tracks)
                {
                    if (track.IsLocked && track.Clips.Any(clip => clip.TimelineEnd > range.Start))
                        throw new InvalidEditException($"Track {track.Name} is locked.");
                    var updated = new List<TimelineClip>();
                    foreach (var clip in track.Clips)
                    {
                        if (clip.TimelineEnd <= range.Start) { updated.Add(clip); continue; }
                        if (clip.TimelineStart >= range.End)
                        {
                            clip.TimelineStart -= range.Duration;
                            updated.Add(clip);
                            continue;
                        }
                        var leftDuration = range.Start > clip.TimelineStart ? range.Start - clip.TimelineStart : RationalTime.Zero;
                        var rightDuration = clip.TimelineEnd > range.End ? clip.TimelineEnd - range.End : RationalTime.Zero;
                        if (leftDuration > RationalTime.Zero)
                        {
                            clip.Duration = leftDuration;
                            updated.Add(clip);
                        }
                        if (rightDuration > RationalTime.Zero)
                        {
                            var right = ProjectCodec.Clone(candidate).Timeline.Tracks.SelectMany(item => item.Clips).First(item => item.Id == clip.Id);
                            if (leftDuration > RationalTime.Zero) right.Id = Guid.NewGuid();
                            right.TimelineStart = range.Start;
                            right.SourceStart += Scale(range.End - clip.TimelineStart, clip.PlaybackRate);
                            right.Duration = rightDuration;
                            updated.Add(right);
                        }
                    }
                    track.Clips = updated.OrderBy(clip => clip.TimelineStart).ToList();
                }
        });
    }

    public void UpdateClip(Guid clipId, Action<TimelineClip> update) => Commit(candidate =>
    {
        var (track, clip) = Find(candidate, clipId);
        if (track.IsLocked) throw new InvalidEditException($"Track {track.Name} is locked.");
        update(clip);
    });

    public bool Undo()
    {
        if (!_undo.TryPop(out var previous)) return false;
        _redo.Push(Project);
        Project = previous;
        return true;
    }

    public bool Redo()
    {
        if (!_redo.TryPop(out var next)) return false;
        _undo.Push(Project);
        Project = next;
        return true;
    }

    private void Commit(Action<CineleafProject> mutation)
    {
        var before = Project;
        var candidate = ProjectCodec.Clone(before);
        try
        {
            mutation(candidate);
            candidate.ModifiedAt = DateTimeOffset.UtcNow;
            ProjectValidator.Validate(candidate);
        }
        catch (InvalidEditException) { throw; }
        catch (Exception error) when (error is ProjectValidationException or ProjectFormatException)
        {
            throw new InvalidEditException("That edit would make the timeline invalid.", error);
        }
        _undo.Push(before);
        while (_undo.Count > HistoryLimit) RemoveOldest(_undo);
        _redo.Clear();
        Project = candidate;
    }

    private static (TimelineTrack Track, TimelineClip Clip) Find(CineleafProject project, Guid clipId)
    {
        foreach (var track in project.Timeline.Tracks)
        {
            var clip = track.Clips.FirstOrDefault(item => item.Id == clipId);
            if (clip is not null) return (track, clip);
        }
        throw new InvalidEditException("The selected clip no longer exists.");
    }

    private static RationalTime Scale(RationalTime time, double factor) => RationalTime.FromSeconds(time.Seconds * factor);

    private static List<RationalTimeRange> MergeRanges(IEnumerable<RationalTimeRange> ranges)
    {
        var ordered = ranges.Where(range => range.Start >= RationalTime.Zero && range.Duration > RationalTime.Zero)
            .OrderBy(range => range.Start).ToArray();
        var merged = new List<RationalTimeRange>();
        foreach (var range in ordered)
        {
            if (merged.Count == 0 || merged[^1].End < range.Start) merged.Add(range);
            else
            {
                var previous = merged[^1];
                var end = previous.End > range.End ? previous.End : range.End;
                merged[^1] = new RationalTimeRange(previous.Start, end - previous.Start);
            }
        }
        return merged;
    }

    private static void RemoveOldest(Stack<CineleafProject> stack)
    {
        var keep = stack.Reverse().Skip(1).ToArray();
        stack.Clear();
        foreach (var project in keep) stack.Push(project);
    }
}
