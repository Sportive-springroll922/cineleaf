using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Cineleaf.Core;

public sealed class ProjectFormatException(string message, Exception? innerException = null) : Exception(message, innerException);

public static class ProjectCodec
{
    private static readonly JsonSerializerOptions Options = CreateOptions();

    public static string Encode(CineleafProject project)
    {
        ProjectValidator.Validate(project);
        return JsonSerializer.Serialize(project, Options);
    }

    public static CineleafProject Decode(string json)
    {
        try
        {
            var migrated = Migrate(JsonNode.Parse(json)?.AsObject() ?? throw new ProjectFormatException("Project JSON is empty."));
            var project = migrated.Deserialize<CineleafProject>(Options) ?? throw new ProjectFormatException("Project JSON is empty.");
            ProjectValidator.Validate(project);
            return project;
        }
        catch (ProjectFormatException) { throw; }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ProjectValidationException)
        {
            throw new ProjectFormatException("The Cineleaf project is damaged or unsupported.", error);
        }
    }

    public static CineleafProject Clone(CineleafProject project) => Decode(Encode(project));

    private static JsonObject Migrate(JsonObject document)
    {
        var version = document["formatVersion"]?.GetValue<int>()
            ?? throw new ProjectFormatException("The project does not contain a format version.");
        if (version > CineleafProject.CurrentFormatVersion)
            throw new ProjectFormatException($"Project version {version} is newer than this version of Cineleaf.");
        if (version < 0) throw new ProjectFormatException($"Project version {version} is invalid.");
        if (version == 0)
        {
            document["formatVersion"] = 1;
            version = 1;
        }
        if (version == 1)
        {
            var tracks = document["timeline"]?["tracks"]?.AsArray();
            if (tracks is not null)
            {
                document["timeline"]!["markers"] ??= new JsonArray();
                foreach (var track in tracks)
                    foreach (var clipNode in track?["clips"]?.AsArray() ?? [])
                    {
                        var clip = clipNode!.AsObject();
                        clip["playbackRate"] ??= 1d;
                        clip["isReversed"] ??= false;
                        clip["role"] ??= "standard";
                        clip["colorAdjustments"] ??= JsonSerializer.SerializeToNode(new ColorAdjustments(), Options);
                        clip["effects"] ??= new JsonArray();
                        clip["keyframes"] ??= JsonSerializer.SerializeToNode(new ClipKeyframes(), Options);
                    }
            }
            document["formatVersion"] = 2;
        }
        return document;
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            PropertyNameCaseInsensitive = false
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        options.Converters.Add(new AppleReferenceDateConverter());
        options.Converters.Add(new NullableAppleReferenceDateConverter());
        return options;
    }

    private sealed class AppleReferenceDateConverter : JsonConverter<DateTimeOffset>
    {
        private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
            Epoch.AddSeconds(reader.GetDouble());
        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
            writer.WriteNumberValue((value.ToUniversalTime() - Epoch).TotalSeconds);
    }

    private sealed class NullableAppleReferenceDateConverter : JsonConverter<DateTimeOffset?>
    {
        private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset? Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
            reader.TokenType == JsonTokenType.Null ? null : Epoch.AddSeconds(reader.GetDouble());
        public override void Write(Utf8JsonWriter writer, DateTimeOffset? value, JsonSerializerOptions options)
        {
            if (value is null) writer.WriteNullValue();
            else writer.WriteNumberValue((value.Value.ToUniversalTime() - Epoch).TotalSeconds);
        }
    }
}

public sealed class ProjectPackageStore(string? recoveryDirectory = null) : IDisposable
{
    private readonly string _recoveryDirectory = recoveryDirectory ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Cineleaf", "Recovery");
    private readonly SemaphoreSlim _ioGate = new(1, 1);

    public async Task SaveAsync(CineleafProject project, string packagePath, CancellationToken cancellationToken = default)
    {
        ValidatePackagePath(packagePath);
        await _ioGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            Directory.CreateDirectory(packagePath);
            var destination = Path.Combine(packagePath, "project.json");
            var temporary = Path.Combine(packagePath, $"project-{Guid.NewGuid():N}.tmp");
            try
            {
                await File.WriteAllTextAsync(temporary, ProjectCodec.Encode(project), cancellationToken).ConfigureAwait(false);
                File.Move(temporary, destination, overwrite: true);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }
        finally
        {
            _ioGate.Release();
        }
    }

    public async Task<CineleafProject> OpenAsync(string packagePath, CancellationToken cancellationToken = default)
    {
        ValidatePackagePath(packagePath);
        await _ioGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!Directory.Exists(packagePath)) throw new ProjectFormatException("The selected Cineleaf project folder does not exist.");
            var projectFile = Path.Combine(packagePath, "project.json");
            if (!File.Exists(projectFile)) throw new ProjectFormatException("The selected folder is missing project.json.");
            return ProjectCodec.Decode(await File.ReadAllTextAsync(projectFile, cancellationToken).ConfigureAwait(false));
        }
        finally
        {
            _ioGate.Release();
        }
    }

    public async Task SaveRecoveryAsync(CineleafProject project, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_recoveryDirectory);
        await File.WriteAllTextAsync(Path.Combine(_recoveryDirectory, $"{project.Id}.json"), ProjectCodec.Encode(project), cancellationToken)
            .ConfigureAwait(false);
    }

    private static void ValidatePackagePath(string path)
    {
        if (!string.Equals(Path.GetExtension(path), ".cineleaf", StringComparison.OrdinalIgnoreCase))
            throw new ProjectFormatException("Cineleaf projects must use the .cineleaf extension.");
    }

    public void Dispose() => _ioGate.Dispose();
}
