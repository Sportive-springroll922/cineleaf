using System.Diagnostics;

namespace Cineleaf.Media;

public sealed class MediaProcessException(string executable, int exitCode, string details)
    : Exception($"{Path.GetFileName(executable)} stopped with error {exitCode}.\n{details}")
{
    public int ExitCode { get; } = exitCode;
    public string Details { get; } = details;
}

public sealed record MediaProcessResult(int ExitCode, string StandardOutput, string StandardError);

public static class MediaProcessRunner
{
    public static async Task<MediaProcessResult> RunAsync(
        string executable,
        IEnumerable<string> arguments,
        Action<string>? outputLine = null,
        CancellationToken cancellationToken = default)
    {
        var startInfo = CreateStartInfo(executable, arguments);
        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        if (!process.Start()) throw new InvalidOperationException($"Could not start {Path.GetFileName(executable)}.");
        using var registration = cancellationToken.Register(() =>
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
        });
        var stdout = new List<string>();
        var stderr = new List<string>();
        var readOutput = ReadLinesAsync(process.StandardOutput, line => { stdout.Add(line); outputLine?.Invoke(line); }, cancellationToken);
        var readError = ReadLinesAsync(process.StandardError, stderr.Add, cancellationToken);
        try
        {
            await Task.WhenAll(process.WaitForExitAsync(cancellationToken), readOutput, readError).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        var output = string.Join(Environment.NewLine, stdout);
        var error = string.Join(Environment.NewLine, stderr);
        if (process.ExitCode != 0) throw new MediaProcessException(executable, process.ExitCode, Tail(error, 8_000));
        return new MediaProcessResult(process.ExitCode, output, error);
    }

    public static ProcessStartInfo CreateStartInfo(string executable, IEnumerable<string> arguments)
    {
        var info = new ProcessStartInfo
        {
            FileName = executable,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        return info;
    }

    private static async Task ReadLinesAsync(StreamReader reader, Action<string> onLine, CancellationToken cancellationToken)
    {
        while (await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false) is { } line) onLine(line);
    }

    private static string Tail(string value, int maximum) => value.Length <= maximum ? value : value[^maximum..];
}
