using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Notebar.Core.Models;
using Notebar.Core.Panel;
using Notebar.Core.Repositories;

namespace Notebar.App.Features.Settings;

/// <summary>The four Settings sections -- General, Activation, Data, About (Task 16 brief) --
/// matching the shipped macOS SettingsTab.swift.</summary>
/// <remarks>
/// Every control here writes through immediately: there is no Save button, matching macOS.
/// General's Theme selection persists via <see cref="IAppStateRepository.SetTheme"/> and is
/// applied live through the <c>applyTheme</c> callback <see cref="Attach"/> is given, which
/// RootPage wires to setting <c>RequestedTheme</c> on itself -- the root of the visual tree
/// every <c>{ThemeResource}</c> in the panel resolves against. Activation's three sliders
/// write through to both the repository (survives relaunch) and the static
/// <see cref="Notebar.App.Settings"/> holder PanelController actually reads on every effect
/// (felt on the very next dwell, not the next relaunch) -- the same split
/// <c>Notebar.App.Settings</c>'s own remarks describe.
/// </remarks>
internal sealed partial class SettingsTab : UserControl
{
    private IAppStateRepository? _appStateRepository;
    private IDiagnosticsRepository? _diagnosticsRepository;
    private Action<Theme>? _applyTheme;

    /// <summary>Guards every ValueChanged/SelectionChanged handler below while Attach is
    /// still setting up the controls' initial values -- setting Slider.Value or
    /// RadioButtons.SelectedIndex programmatically raises the same event a real user
    /// interaction would, and without this guard that would re-persist the value that was
    /// just read from the repository right back into it (harmless) but also re-invoke
    /// applyTheme before RootPage even exists to receive it in some call orders.</summary>
    private bool _initializing;

    internal SettingsTab() => InitializeComponent();

    /// <summary>Wires everything up. Called once by RootPage.AttachController, mirroring
    /// NotesTab.Attach/TasksTab.Attach.</summary>
    internal void Attach(
        IAppStateRepository appStateRepository,
        IDiagnosticsRepository diagnosticsRepository,
        Action<Theme> applyTheme)
    {
        _appStateRepository = appStateRepository;
        _diagnosticsRepository = diagnosticsRepository;
        _applyTheme = applyTheme;

        _initializing = true;

        ThemeRadioButtons.SelectedIndex = appStateRepository.GetTheme() switch
        {
            Theme.Light => 1,
            Theme.Dark => 2,
            _ => 0,
        };

        // Minimum/Maximum before Value on every slider -- WinUI clamps an assigned Value
        // into whatever [Minimum, Maximum] the control already has, and the default range
        // (0-10) would silently clamp e.g. ExitSlop's stored value (0-100) if Value were set
        // first.
        EdgeDwellSlider.Minimum = PanelTiming.EdgeDwellMin;
        EdgeDwellSlider.Maximum = PanelTiming.EdgeDwellMax;
        EdgeDwellSlider.Value = appStateRepository.GetEdgeDwell();

        ExitDwellSlider.Minimum = PanelTiming.ExitDwellMin;
        ExitDwellSlider.Maximum = PanelTiming.ExitDwellMax;
        ExitDwellSlider.Value = appStateRepository.GetExitDwell();

        ExitSlopSlider.Minimum = PanelTiming.ExitSlopMin;
        ExitSlopSlider.Maximum = PanelTiming.ExitSlopMax;
        ExitSlopSlider.Value = appStateRepository.GetExitSlop();

        UpdateSliderLabels();

        VersionLabel.Text = AppVersion.DisplayText;

        RefreshData();

        _initializing = false;
    }

    /// <summary>Re-reads Data's facts from the repository. Called once from Attach, and again
    /// by RootPage every time the rail switches to this tab -- size on disk changes as the
    /// user writes notes, so a value read once at launch would go stale the moment anything
    /// was typed.</summary>
    internal void RefreshData()
    {
        if (_diagnosticsRepository is null) return;
        DatabaseDiagnostics diagnostics = _diagnosticsRepository.Snapshot();

        bool inMemory = diagnostics.Path is null;
        InMemoryWarning.Visibility = inMemory ? Visibility.Visible : Visibility.Collapsed;

        DatabasePathLabel.Text = diagnostics.Path
            ?? "Using a temporary in-memory store — the on-disk database couldn't be opened.";
        RevealButton.IsEnabled = diagnostics.Path is not null;

        DatabaseSizeLabel.Text = diagnostics.SizeOnDisk is { } size ? FormatBytes(size) : "—";

        MigrationsLabel.Text = diagnostics.AppliedMigrations.Count == 0
            ? "none"
            : string.Join(", ", diagnostics.AppliedMigrations);
    }

    // --- General ---

    private void OnThemeSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_initializing || _appStateRepository is null || _applyTheme is null) return;
        Theme theme = ThemeRadioButtons.SelectedIndex switch
        {
            1 => Theme.Light,
            2 => Theme.Dark,
            _ => Theme.System,
        };
        _appStateRepository.SetTheme(theme);
        _applyTheme(theme);
    }

    // --- Activation ---

    private void OnEdgeDwellChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_initializing || _appStateRepository is null) return;
        Notebar.App.Settings.EdgeDwell = e.NewValue;
        _appStateRepository.SetEdgeDwell(e.NewValue);
        UpdateSliderLabels();
    }

    private void OnExitDwellChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_initializing || _appStateRepository is null) return;
        Notebar.App.Settings.ExitDwell = e.NewValue;
        _appStateRepository.SetExitDwell(e.NewValue);
        UpdateSliderLabels();
    }

    private void OnExitSlopChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_initializing || _appStateRepository is null) return;
        Notebar.App.Settings.ExitSlop = e.NewValue;
        _appStateRepository.SetExitSlop(e.NewValue);
        UpdateSliderLabels();
    }

    private void UpdateSliderLabels()
    {
        EdgeDwellValueLabel.Text = $"{Math.Round(EdgeDwellSlider.Value * 1000)} ms";
        ExitDwellValueLabel.Text = $"{Math.Round(ExitDwellSlider.Value * 1000)} ms";
        ExitSlopValueLabel.Text = $"{Math.Round(ExitSlopSlider.Value)} pt";
    }

    // --- Data ---

    private static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB"];
        double value = bytes;
        int unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }
        return unit == 0 ? $"{bytes} B" : $"{value:0.#} {units[unit]}";
    }

    private void OnRevealClick(object sender, RoutedEventArgs e)
    {
        string? path = _diagnosticsRepository?.Snapshot().Path;
        if (path is null) return;
        try
        {
            // The Windows equivalent of NSWorkspace.activateFileViewerSelecting: opens File
            // Explorer with the database file pre-selected, rather than just its containing
            // folder.
            Process.Start("explorer.exe", $"/select,\"{path}\"");
        }
        catch (Exception ex)
        {
            NotebarLog.Error($"failed to reveal the database in File Explorer: {ex.GetType().Name}: {ex.Message}");
        }
    }

    private async void OnExportClick(object sender, RoutedEventArgs e)
    {
        if (_diagnosticsRepository is null) return;
        IntPtr hwnd = ((App)Application.Current).Window?.Handle ?? IntPtr.Zero;
        if (hwnd == IntPtr.Zero) return;
        await DiagnosticsExporter.ExportAsync(hwnd, _diagnosticsRepository);
    }

    // --- About ---

    private void OnQuitClick(object sender, RoutedEventArgs e) => ((App)Application.Current).Quit();
}
