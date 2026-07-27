using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using Cineleaf.Core;
using Microsoft.Win32;

namespace Cineleaf.Windows;

public partial class ExportWindow : Window, IDisposable
{
    private readonly EditorViewModel _viewModel;
    private CancellationTokenSource? _cancellation;

    public ExportWindow(EditorViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        PathBox.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), viewModel.Project.Name + ".mp4");
        _viewModel.ProgressChanged += ViewModel_ProgressChanged;
        Closed += (_, _) => Dispose();
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog { Filter = "MP4 video|*.mp4", FileName = Path.GetFileName(PathBox.Text), InitialDirectory = Path.GetDirectoryName(PathBox.Text) };
        if (dialog.ShowDialog(this) == true) PathBox.Text = dialog.FileName;
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(PathBox.Text)) { ResultText.Text = "Choose an output file."; return; }
        _cancellation = new CancellationTokenSource();
        ExportButton.IsEnabled = false;
        try
        {
            var preset = Parse<ExportResolutionPreset>(ResolutionBox);
            var resolution = ResolutionFor(preset, _viewModel.Project.Canvas);
            var result = await _viewModel.ExportAsync(PathBox.Text, resolution, Parse<ExportCodec>(CodecBox), Parse<ExportQuality>(QualityBox), _cancellation.Token);
            ResultText.Text = $"✓ {Path.GetFileName(result.Path)} — {result.Resolution.Width}×{result.Resolution.Height} — {result.Duration.Seconds.ToString("0.0", CultureInfo.CurrentCulture)} s";
        }
        catch (OperationCanceledException) { ResultText.Text = FindResource("Cancel").ToString(); }
        catch (Exception error) { ResultText.Text = error.Message; }
        finally { ExportButton.IsEnabled = true; _cancellation.Dispose(); _cancellation = null; }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (_cancellation is null) Close(); else _cancellation.Cancel();
    }

    private void ViewModel_ProgressChanged(object? sender, double value) => Dispatcher.Invoke(() => Progress.Value = value);
    private static T Parse<T>(ComboBox box) where T : struct, Enum =>
        box.SelectedItem is ComboBoxItem { Tag: string value } && Enum.TryParse<T>(value, out var result) ? result : default;

    private static Resolution ResolutionFor(ExportResolutionPreset preset, Resolution canvas)
    {
        var longEdge = preset switch { ExportResolutionPreset.P720 => 1280, ExportResolutionPreset.P1440 => 2560, ExportResolutionPreset.P2160 => 3840, _ => 1920 };
        var scale = (double)longEdge / Math.Max(canvas.Width, canvas.Height);
        return new Resolution(Math.Max(2, (int)Math.Round(canvas.Width * scale / 2) * 2), Math.Max(2, (int)Math.Round(canvas.Height * scale / 2) * 2));
    }

    public void Dispose()
    {
        _viewModel.ProgressChanged -= ViewModel_ProgressChanged;
        _cancellation?.Cancel();
        _cancellation?.Dispose();
        _cancellation = null;
        GC.SuppressFinalize(this);
    }
}
