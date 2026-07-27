using System.Windows;
using System.Windows.Controls;
using Cineleaf.Core;

namespace Cineleaf.Windows;

public partial class NewProjectWindow : Window
{
    public NewProjectWindow() => InitializeComponent();
    public string ProjectName => NameBox.Text;
    public CanvasPreset Canvas => Parse<CanvasPreset>(CanvasBox);
    public ProjectFrameRate FrameRate => Parse<ProjectFrameRate>(FrameRateBox);
    private void Create_Click(object sender, RoutedEventArgs e) { DialogResult = true; Close(); }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }
    private static T Parse<T>(ComboBox box) where T : struct, Enum =>
        box.SelectedItem is ComboBoxItem { Tag: string value } && Enum.TryParse<T>(value, out var result) ? result : default;
}
