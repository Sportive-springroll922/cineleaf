namespace Cineleaf.Core;

public sealed class ProjectValidationException(string message) : Exception(message);

public static class ProjectValidator
{
    public static void Validate(CineleafProject project)
    {
        ArgumentNullException.ThrowIfNull(project);
        if (project.FormatVersion != CineleafProject.CurrentFormatVersion)
            throw new ProjectValidationException($"Unsupported project version {project.FormatVersion}.");
        if (project.Canvas.Width <= 0 || project.Canvas.Height <= 0)
            throw new ProjectValidationException("Canvas dimensions must be positive.");

        var identifiers = new HashSet<Guid> { project.Id };
        var assets = project.Assets.ToDictionary(asset => asset.Id);
        foreach (var asset in project.Assets)
        {
            if (!identifiers.Add(asset.Id)) throw new ProjectValidationException($"Duplicate identifier {asset.Id}.");
        }

        foreach (var marker in project.Timeline.Markers)
        {
            if (!identifiers.Add(marker.Id)) throw new ProjectValidationException($"Duplicate identifier {marker.Id}.");
            if (marker.Time < RationalTime.Zero) throw new ProjectValidationException($"Marker {marker.Id} has a negative time.");
        }

        foreach (var track in project.Timeline.Tracks)
        {
            if (!identifiers.Add(track.Id)) throw new ProjectValidationException($"Duplicate identifier {track.Id}.");
            var ordered = track.Clips.OrderBy(clip => clip.TimelineStart).ToList();
            for (var index = 0; index < ordered.Count; index++)
            {
                var clip = ordered[index];
                if (!identifiers.Add(clip.Id)) throw new ProjectValidationException($"Duplicate identifier {clip.Id}.");
                if (clip.TimelineStart < RationalTime.Zero || clip.SourceStart < RationalTime.Zero || clip.Duration <= RationalTime.Zero)
                    throw new ProjectValidationException($"Clip {clip.Id} has invalid time values.");
                if (index > 0 && ordered[index - 1].TimelineEnd > clip.TimelineStart)
                    throw new ProjectValidationException($"Clips {ordered[index - 1].Id} and {clip.Id} overlap.");
                if ((clip.Kind == ClipKind.Audio ? TrackKind.Audio : TrackKind.Video) != track.Kind)
                    throw new ProjectValidationException($"Clip {clip.Id} is on an incompatible track.");
                if (clip.Kind == ClipKind.Text)
                {
                    if (clip.TextStyle is null || clip.AssetId is not null)
                        throw new ProjectValidationException($"Text clip {clip.Id} is malformed.");
                }
                else if (clip.AssetId is not { } assetId || !assets.TryGetValue(assetId, out var asset))
                {
                    throw new ProjectValidationException($"Clip {clip.Id} references missing media.");
                }
                else if (clip.Kind != ClipKind.Image && asset.Metadata.Duration is { } sourceDuration &&
                         clip.SourceStart + RationalTime.FromSeconds(clip.Duration.Seconds * clip.PlaybackRate) > sourceDuration)
                {
                    throw new ProjectValidationException($"Clip {clip.Id} extends beyond its source media.");
                }
                if (!double.IsFinite(clip.PlaybackRate) || clip.PlaybackRate is < 0.25 or > 4)
                    throw new ProjectValidationException($"Clip {clip.Id} has an invalid playback rate.");
                if (!double.IsFinite(clip.Opacity) || clip.Opacity is < 0 or > 1)
                    throw new ProjectValidationException($"Clip {clip.Id} has invalid opacity.");
                if (!double.IsFinite(clip.AudioVolume) || clip.AudioVolume is < 0 or > 2)
                    throw new ProjectValidationException($"Clip {clip.Id} has invalid volume.");
                ValidateTransform(clip);
                ValidateFades(clip);
                ValidateAdvancedProperties(clip, identifiers);
            }
        }
    }

    private static void ValidateAdvancedProperties(TimelineClip clip, HashSet<Guid> identifiers)
    {
        var color = clip.ColorAdjustments;
        var colorValues = new[] { color.Exposure, color.Contrast, color.Saturation, color.Temperature, color.Tint,
            color.Highlights, color.Shadows, color.Sharpen, color.Vignette };
        if (colorValues.Any(value => !double.IsFinite(value)) || color.Exposure is < -4 or > 4 ||
            color.Contrast is < 0 or > 4 || color.Saturation is < 0 or > 4 ||
            color.Temperature is < -1 or > 1 || color.Tint is < -1 or > 1 ||
            color.Highlights is < -1 or > 1 || color.Shadows is < -1 or > 1 ||
            color.Sharpen is < 0 or > 1 || color.Vignette is < 0 or > 1)
            throw new ProjectValidationException($"Clip {clip.Id} has invalid color adjustments.");

        foreach (var effect in clip.Effects)
        {
            if (!identifiers.Add(effect.Id)) throw new ProjectValidationException($"Duplicate identifier {effect.Id}.");
            if (!double.IsFinite(effect.Amount) || effect.Amount is < 0 or > 1)
                throw new ProjectValidationException($"Clip {clip.Id} has an invalid effect.");
        }

        foreach (var transition in new[] { clip.TransitionIn, clip.TransitionOut }.OfType<ClipTransition>())
        {
            if (transition.Duration <= RationalTime.Zero || transition.Duration > clip.Duration)
                throw new ProjectValidationException($"Clip {clip.Id} has an invalid transition.");
        }

        ValidateKeyframes(clip, clip.Keyframes.PositionX, static _ => true);
        ValidateKeyframes(clip, clip.Keyframes.PositionY, static _ => true);
        ValidateKeyframes(clip, clip.Keyframes.RotationDegrees, static _ => true);
        ValidateKeyframes(clip, clip.Keyframes.Scale, static value => value > 0);
        ValidateKeyframes(clip, clip.Keyframes.Opacity, static value => value is >= 0 and <= 1);
        ValidateKeyframes(clip, clip.Keyframes.Volume, static value => value is >= 0 and <= 2);

        if ((clip.Role == ClipRole.Subtitle && clip.Kind != ClipKind.Text) ||
            (clip.Role == ClipRole.Voiceover && clip.Kind != ClipKind.Audio))
            throw new ProjectValidationException($"Clip {clip.Id} has an incompatible role.");
    }

    private static void ValidateKeyframes(TimelineClip clip, List<ScalarKeyframe> frames, Func<double, bool> valueIsValid)
    {
        for (var index = 0; index < frames.Count; index++)
        {
            var frame = frames[index];
            if (frame.Time < RationalTime.Zero || frame.Time > clip.Duration || !double.IsFinite(frame.Value) ||
                !valueIsValid(frame.Value) || (index > 0 && frames[index - 1].Time >= frame.Time))
                throw new ProjectValidationException($"Clip {clip.Id} has invalid keyframes.");
        }
    }

    private static void ValidateTransform(TimelineClip clip)
    {
        var transform = clip.Transform;
        var numbers = new[] { transform.PositionX, transform.PositionY, transform.Scale, transform.RotationDegrees,
            transform.CropTop, transform.CropLeading, transform.CropBottom, transform.CropTrailing };
        if (numbers.Any(value => !double.IsFinite(value)) || transform.Scale <= 0 ||
            new[] { transform.CropTop, transform.CropLeading, transform.CropBottom, transform.CropTrailing }
                .Any(value => value is < 0 or > 1))
            throw new ProjectValidationException($"Clip {clip.Id} has an invalid transform.");
    }

    private static void ValidateFades(TimelineClip clip)
    {
        var fades = new[] { clip.Fades.VideoIn, clip.Fades.VideoOut, clip.Fades.AudioIn, clip.Fades.AudioOut };
        if (fades.Any(fade => fade < RationalTime.Zero || fade > clip.Duration) ||
            clip.Fades.VideoIn + clip.Fades.VideoOut > clip.Duration ||
            clip.Fades.AudioIn + clip.Fades.AudioOut > clip.Duration)
            throw new ProjectValidationException($"Clip {clip.Id} has invalid fades.");
    }
}
