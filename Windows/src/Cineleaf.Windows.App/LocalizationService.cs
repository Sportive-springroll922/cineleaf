using System.Globalization;
using System.Text.Json;
using System.Windows;

namespace Cineleaf.Windows;

public static class LocalizationService
{
    private static readonly string PreferencesPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Cineleaf", "preferences.json");

    public static string Preference { get; private set; } = "system";

    public static void Initialize()
    {
        try
        {
            if (File.Exists(PreferencesPath))
                Preference = JsonSerializer.Deserialize<Preferences>(File.ReadAllText(PreferencesPath))?.Language ?? "system";
        }
        catch (JsonException) { Preference = "system"; }
        Apply(Preference, persist: false);
    }

    public static void Apply(string language, bool persist = true)
    {
        Preference = language is "en" or "es" ? language : "system";
        var effective = Preference == "system" ? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName : Preference;
        if (effective != "es") effective = "en";
        var dictionaries = Application.Current.Resources.MergedDictionaries;
        var current = dictionaries.FirstOrDefault(dictionary => dictionary.Source?.OriginalString.Contains("Strings.", StringComparison.Ordinal) == true);
        var replacement = new ResourceDictionary { Source = new Uri($"Resources/Strings.{effective}.xaml", UriKind.Relative) };
        if (current is null) dictionaries.Insert(0, replacement);
        else dictionaries[dictionaries.IndexOf(current)] = replacement;
        if (!persist) return;
        Directory.CreateDirectory(Path.GetDirectoryName(PreferencesPath)!);
        File.WriteAllText(PreferencesPath, JsonSerializer.Serialize(new Preferences(Preference)));
    }

    private sealed record Preferences(string Language);
}
