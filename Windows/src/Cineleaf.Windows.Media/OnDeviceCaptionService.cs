using System.Globalization;
using System.Speech.Recognition;
using Cineleaf.Core;

namespace Cineleaf.Media;

public sealed class OnDeviceCaptionService(FfmpegToolchain toolchain)
{
    public static IReadOnlyList<CultureInfo> AvailableCultures => SpeechRecognitionEngine.InstalledRecognizers()
        .Select(recognizer => recognizer.Culture).DistinctBy(culture => culture.Name).OrderBy(culture => culture.DisplayName).ToArray();

    public async Task<IReadOnlyList<SubtitleCue>> TranscribeAsync(
        string mediaPath,
        CultureInfo culture,
        CancellationToken cancellationToken = default)
    {
        var recognizerInfo = SpeechRecognitionEngine.InstalledRecognizers()
            .FirstOrDefault(item => item.Culture.Name.Equals(culture.Name, StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException($"Windows does not have the {culture.DisplayName} offline speech pack installed.");
        var wave = Path.Combine(Path.GetTempPath(), $"cineleaf-speech-{Guid.NewGuid():N}.wav");
        try
        {
            await MediaProcessRunner.RunAsync(toolchain.FfmpegPath,
            [
                "-hide_banner", "-loglevel", "error", "-y", "-i", mediaPath, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wave
            ], cancellationToken: cancellationToken).ConfigureAwait(false);
            return await RecognizeAsync(wave, recognizerInfo, cancellationToken).ConfigureAwait(false);
        }
        finally { if (File.Exists(wave)) File.Delete(wave); }
    }

    private static Task<IReadOnlyList<SubtitleCue>> RecognizeAsync(
        string wave,
        RecognizerInfo recognizerInfo,
        CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<IReadOnlyList<SubtitleCue>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var engine = new SpeechRecognitionEngine(recognizerInfo.Id);
        var cues = new List<SubtitleCue>();
        engine.LoadGrammar(new DictationGrammar());
        engine.SetInputToWaveFile(wave);
        engine.SpeechRecognized += (_, eventArgs) =>
        {
            if (eventArgs.Result.Confidence < 0.25 || string.IsNullOrWhiteSpace(eventArgs.Result.Text)) return;
            var audio = eventArgs.Result.Audio;
            cues.Add(new SubtitleCue(
                RationalTime.FromSeconds(audio.AudioPosition.TotalSeconds),
                RationalTime.FromSeconds(Math.Max(audio.Duration.TotalSeconds, 0.2)),
                eventArgs.Result.Text.Trim()));
        };
        engine.RecognizeCompleted += (_, eventArgs) =>
        {
            engine.Dispose();
            if (eventArgs.Cancelled) completion.TrySetCanceled(cancellationToken);
            else if (eventArgs.Error is not null) completion.TrySetException(eventArgs.Error);
            else completion.TrySetResult(cues.OrderBy(cue => cue.Start).ToArray());
        };
        var registration = cancellationToken.Register(engine.RecognizeAsyncCancel);
        _ = completion.Task.ContinueWith(_ => registration.Dispose(), CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        engine.RecognizeAsync(RecognizeMode.Multiple);
        return completion.Task;
    }
}
