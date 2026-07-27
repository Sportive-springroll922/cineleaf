using System.Windows;

namespace Cineleaf.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        LocalizationService.Initialize();
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
        if (e.Args.FirstOrDefault(path => Directory.Exists(path) && Path.GetExtension(path).Equals(".cineleaf", StringComparison.OrdinalIgnoreCase)) is { } project)
            _ = window.OpenFromCommandLineAsync(project);
    }
}
