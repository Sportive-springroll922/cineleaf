using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class DefaultModelTests
{
    [Fact]
    public void NewClipUsesValidZeroTimes()
    {
        var clip = new TimelineClip { Kind = ClipKind.Text, TextStyle = new TextStyle(), Duration = new RationalTime(1, 1) };

        Assert.Equal(RationalTime.Zero, clip.TimelineStart);
        Assert.Equal(RationalTime.Zero, clip.SourceStart);
        Assert.Equal(new RationalTime(1, 1), clip.TimelineEnd);
    }
}
