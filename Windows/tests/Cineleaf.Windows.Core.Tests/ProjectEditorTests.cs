using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class ProjectEditorTests
{
    [Fact]
    public void SplitPreservesSourceAndTimelineRanges()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var original = project.Timeline.Tracks[0].Clips[0];
        var editor = new ProjectEditor(project);

        var rightId = editor.Split(original.Id, new RationalTime(4, 1));

        var clips = editor.Project.Timeline.Tracks[0].Clips;
        Assert.Equal(new RationalTime(4, 1), clips[0].Duration);
        Assert.Equal(new RationalTime(4, 1), clips[1].TimelineStart);
        Assert.Equal(new RationalTime(4, 1), clips[1].SourceStart);
        Assert.Equal(rightId, clips[1].Id);
    }

    [Fact]
    public void RippleDeleteClosesDeletedRange()
    {
        var project = ProjectFixtures.ThreeClipProject();
        var editor = new ProjectEditor(project);
        var middle = project.Timeline.Tracks[0].Clips[1];

        editor.Delete(new[] { middle.Id }, ripple: true);

        Assert.Equal(new RationalTime(10, 1), editor.Project.Timeline.Tracks[0].Clips[1].TimelineStart);
    }

    [Fact]
    public void UndoRedoRestoresACommittedEdit()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var editor = new ProjectEditor(project);
        var clipId = project.Timeline.Tracks[0].Clips[0].Id;

        editor.Move(clipId, new RationalTime(3, 1));
        Assert.Equal(new RationalTime(3, 1), editor.Project.Timeline.Tracks[0].Clips[0].TimelineStart);
        Assert.True(editor.Undo());
        Assert.Equal(RationalTime.Zero, editor.Project.Timeline.Tracks[0].Clips[0].TimelineStart);
        Assert.True(editor.Redo());
        Assert.Equal(new RationalTime(3, 1), editor.Project.Timeline.Tracks[0].Clips[0].TimelineStart);
    }

    [Fact]
    public void InvalidOverlapDoesNotMutateProject()
    {
        var project = ProjectFixtures.ThreeClipProject();
        var editor = new ProjectEditor(project);
        var last = project.Timeline.Tracks[0].Clips[2];

        Assert.Throws<InvalidEditException>(() => editor.Move(last.Id, new RationalTime(5, 1)));
        Assert.Equal(new RationalTime(20, 1), editor.Project.Timeline.Tracks[0].Clips[2].TimelineStart);
    }
}
