using System.Text.Json;
using Cineleaf.Core;

namespace Cineleaf.Windows.Core.Tests;

public sealed class ProjectCodecTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "CineleafTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public void EncodesMacCompatibleVersionTwoJson()
    {
        var created = new DateTimeOffset(2026, 7, 27, 10, 0, 0, TimeSpan.Zero);
        var project = ProjectFixtures.SimpleProject(created);

        var json = ProjectCodec.Encode(project);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        Assert.Equal(2, root.GetProperty("formatVersion").GetInt32());
        Assert.Equal("landscape16x9", root.GetProperty("canvasPreset").GetString());
        Assert.Equal("fps30", root.GetProperty("frameRate").GetString());
        Assert.Equal(806_839_200d, root.GetProperty("createdAt").GetDouble());
        Assert.Equal(1, root.GetProperty("timeline").GetProperty("tracks")[0].GetProperty("clips").GetArrayLength());
    }

    [Fact]
    public void MigratesVersionOneAndRoundTripsAllEditingFields()
    {
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);
        var json = ProjectCodec.Encode(project);
        var node = JsonNode.Parse(json)!.AsObject();
        node["formatVersion"] = 1;
        var clip = node["timeline"]!["tracks"]![0]!["clips"]![0]!.AsObject();
        foreach (var key in new[] { "playbackRate", "isReversed", "role", "colorAdjustments", "effects", "keyframes" })
        {
            clip.Remove(key);
        }

        var migrated = ProjectCodec.Decode(node.ToJsonString());

        Assert.Equal(2, migrated.FormatVersion);
        Assert.Equal(1d, migrated.Timeline.Tracks[0].Clips[0].PlaybackRate);
        Assert.Empty(migrated.Timeline.Tracks[0].Clips[0].Effects);
        Assert.Equal(project.Name, ProjectCodec.Decode(ProjectCodec.Encode(migrated)).Name);
    }

    [Fact]
    public async Task PackageSaveIsAtomicAndReopens()
    {
        Directory.CreateDirectory(_root);
        var package = Path.Combine(_root, "Edit.cineleaf");
        var store = new ProjectPackageStore(Path.Combine(_root, "Recovery"));
        var project = ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow);

        await store.SaveAsync(project, package);
        var reopened = await store.OpenAsync(package);

        Assert.Equal(project.Id, reopened.Id);
        Assert.True(File.Exists(Path.Combine(package, "project.json")));
        Assert.Empty(Directory.EnumerateFiles(package, "*.tmp"));
    }

    [Fact]
    public void RejectsFutureProjectVersion()
    {
        var json = ProjectCodec.Encode(ProjectFixtures.SimpleProject(DateTimeOffset.UtcNow));
        var node = JsonNode.Parse(json)!.AsObject();
        node["formatVersion"] = 999;

        var error = Assert.Throws<ProjectFormatException>(() => ProjectCodec.Decode(node.ToJsonString()));
        Assert.Contains("999", error.Message, StringComparison.Ordinal);
    }

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true);
    }
}
