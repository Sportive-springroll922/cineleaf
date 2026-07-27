using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Cineleaf.Windows.Core.Tests;

public sealed partial class WindowsLocalizationTests
{
    [Fact]
    public void EnglishAndSpanishContainExactlyTheSameKeys()
    {
        var directory = Path.Combine(AppContext.BaseDirectory, "Localization");
        var english = Keys(Path.Combine(directory, "Strings.en.xaml"));
        var spanish = Keys(Path.Combine(directory, "Strings.es.xaml"));

        Assert.NotEmpty(english);
        Assert.Equal(english, spanish);
    }

    [Fact]
    public void EveryDynamicStringUsedByAWindowExists()
    {
        var directory = Path.Combine(AppContext.BaseDirectory, "Localization");
        var keys = Keys(Path.Combine(directory, "Strings.en.xaml"));
        var used = Directory.EnumerateFiles(Path.Combine(directory, "Views"), "*.xaml")
            .SelectMany(path => DynamicResourceRegex().Matches(File.ReadAllText(path)).Select(match => match.Groups[1].Value))
            .ToHashSet(StringComparer.Ordinal);

        Assert.Empty(used.Except(keys));
    }

    private static SortedSet<string> Keys(string path)
    {
        XNamespace x = "http://schemas.microsoft.com/winfx/2006/xaml";
        return new SortedSet<string>(XDocument.Load(path).Root!.Elements().Select(element => element.Attribute(x + "Key")?.Value)
            .Where(value => value is not null).Select(value => value!), StringComparer.Ordinal);
    }

    [GeneratedRegex(@"\{DynamicResource\s+([A-Za-z0-9]+)\}", RegexOptions.CultureInvariant)]
    private static partial Regex DynamicResourceRegex();
}
