using System.Numerics;
using System.Text.Json.Serialization;

namespace Cineleaf.Core;

public readonly record struct RationalTime : IComparable<RationalTime>
{
    public static RationalTime Zero { get; } = new(0, 1);

    [JsonConstructor]
    public RationalTime(long value, int timescale)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(timescale);
        ArgumentOutOfRangeException.ThrowIfEqual(value, long.MinValue);
        var divisor = GreatestCommonDivisor(Math.Abs(value), timescale);
        Value = value / divisor;
        Timescale = checked((int)(timescale / divisor));
    }

    public long Value { get; }
    public int Timescale { get; }
    [JsonIgnore] public double Seconds => (double)Value / Timescale;

    public static RationalTime FromSeconds(double seconds, int preferredTimescale = 60_000)
    {
        if (!double.IsFinite(seconds)) throw new ArgumentOutOfRangeException(nameof(seconds));
        return new RationalTime(checked((long)Math.Round(seconds * preferredTimescale)), preferredTimescale);
    }

    public int CompareTo(RationalTime other) =>
        ((BigInteger)Value * other.Timescale).CompareTo((BigInteger)other.Value * Timescale);

    public static bool operator <(RationalTime left, RationalTime right) => left.CompareTo(right) < 0;
    public static bool operator >(RationalTime left, RationalTime right) => left.CompareTo(right) > 0;
    public static bool operator <=(RationalTime left, RationalTime right) => left.CompareTo(right) <= 0;
    public static bool operator >=(RationalTime left, RationalTime right) => left.CompareTo(right) >= 0;

    public static RationalTime operator +(RationalTime left, RationalTime right)
    {
        var common = LeastCommonMultiple(left.Timescale, right.Timescale);
        return new RationalTime(checked(left.Value * (common / left.Timescale) + right.Value * (common / right.Timescale)), common);
    }

    public static RationalTime operator -(RationalTime left, RationalTime right) =>
        left + new RationalTime(checked(-right.Value), right.Timescale);

    public static RationalTime operator *(RationalTime time, long multiplier) =>
        new(checked(time.Value * multiplier), time.Timescale);

    public RationalTime Clamp(RationalTime minimum, RationalTime maximum) =>
        this < minimum ? minimum : this > maximum ? maximum : this;

    private static int LeastCommonMultiple(int left, int right)
    {
        var value = checked((long)left / GreatestCommonDivisor(left, right) * right);
        if (value > int.MaxValue) throw new OverflowException("Timescale overflow.");
        return (int)value;
    }

    private static long GreatestCommonDivisor(long left, long right)
    {
        while (right != 0)
        {
            (left, right) = (right, left % right);
        }
        return Math.Max(left, 1);
    }
}

public readonly record struct RationalTimeRange(RationalTime Start, RationalTime Duration)
{
    [JsonIgnore] public RationalTime End => Start + Duration;
    public bool Contains(RationalTime time) => time >= Start && time < End;
    public bool Intersects(RationalTimeRange other) => Start < other.End && other.Start < End;
}

public readonly record struct RationalRate
{
    [JsonConstructor]
    public RationalRate(int numerator, int denominator = 1)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(numerator);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(denominator);
        Numerator = numerator;
        Denominator = denominator;
    }

    public int Numerator { get; }
    public int Denominator { get; }
    [JsonIgnore] public double FramesPerSecond => (double)Numerator / Denominator;
    [JsonIgnore] public RationalTime FrameDuration => new(Denominator, Numerator);
}
