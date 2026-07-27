using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class RationalTimeTests
{
    [Fact]
    public void NormalizesAndCalculatesWithoutFloatingPointDrift()
    {
        Assert.Equal(new RationalTime(1, 2), new RationalTime(30, 60));
        Assert.Equal(new RationalTime(5, 6), new RationalTime(1, 2) + new RationalTime(1, 3));
        Assert.Equal(new RationalTime(1, 6), new RationalTime(1, 2) - new RationalTime(1, 3));
    }

    [Fact]
    public void RejectsInvalidTimescale()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new RationalTime(1, 0));
    }
}
