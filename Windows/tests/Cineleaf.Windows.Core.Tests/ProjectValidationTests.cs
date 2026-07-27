using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class ProjectValidationTests
{
    [Fact]
    public void RejectsClipThatRunsPastSourceAtPlaybackSpeed()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var clip = project.Timeline.Tracks[0].Clips[0];
        clip.SourceStart = new RationalTime(20, 1);
        clip.PlaybackRate = 2;

        var error = Assert.Throws<ProjectValidationException>(() => ProjectValidator.Validate(project));

        Assert.Contains("source media", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RejectsInvalidAdvancedEditingValues()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        project.Timeline.Tracks[0].Clips[0].Effects = [new VideoEffect { Amount = double.NaN }];

        Assert.Throws<ProjectValidationException>(() => ProjectValidator.Validate(project));
    }

    [Fact]
    public void RejectsUnorderedKeyframesAndInvalidRoles()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var clip = project.Timeline.Tracks[0].Clips[0];
        clip.Keyframes.Opacity = [new(new RationalTime(2, 1), 0.5), new(new RationalTime(1, 1), 0.8)];
        Assert.Throws<ProjectValidationException>(() => ProjectValidator.Validate(project));

        clip.Keyframes.Opacity.Clear();
        clip.Role = ClipRole.Subtitle;
        Assert.Throws<ProjectValidationException>(() => ProjectValidator.Validate(project));
    }
}
