using System.Diagnostics;
using Microsoft.UI.Dispatching;
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
/// There is no Save button anywhere in this tab, matching macOS -- every control writes
/// through on its own. General's Theme selection persists via
/// <see cref="IAppStateRepository.SetTheme"/> and is applied live through the
/// <c>applyTheme</c> callback <see cref="Attach"/> is given, which RootPage wires to setting
/// <c>RequestedTheme</c> on itself -- the root of the visual tree every
/// <c>{ThemeResource}</c> in the panel resolves against. Activation's three sliders write to
/// two places at two different speeds: the static <see cref="Notebar.App.Settings"/> holder
/// PanelController actually reads on every effect updates on every tick, unthrottled (felt
/// on the very next dwell), while the repository write (needed only to survive a relaunch)
/// is debounced -- see <see cref="SliderCommitDelay"/>.
/// </remarks>
internal sealed partial class SettingsTab : UserControl
{
    /// <summary>How long a slider must sit still before its value is written to the
    /// repository. Matches the note editor's own 400ms save debounce (editor.js) in spirit,
    /// not literally shared code -- that debounce lives in guest-side JS behind a WebView2
    /// boundary this tab has no access to, so this is DispatcherQueueTimer, the WinUI-side
    /// idiom NoteEditorHost's own focus-poll timer and CursorMonitor already use.</summary>
    private static readonly TimeSpan SliderCommitDelay = TimeSpan.FromMilliseconds(400);

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

    // One-shot (IsRepeating = false) per slider: Stop()+Start() on every tick restarts the
    // delay window, so only the LAST value in a drag (or a burst of arrow-key presses) is
    // ever written -- a Slider.ValueChanged fires continuously during a drag, and writing to
    // SQLite on every one of those (up to ~50 per gesture, at this control's StepFrequency)
    // would be a synchronous disk write on the UI thread on every tick. The in-memory
    // Notebar.App.Settings.* value it pairs with is still updated on every tick, unthrottled
    // -- that is what makes the panel feel the new timing on its very next dwell, and only
    // the repository write (which only has to survive a relaunch, not any single tick) is
    // debounced.
    private readonly DispatcherQueueTimer _edgeDwellCommitTimer;
    private readonly DispatcherQueueTimer _exitDwellCommitTimer;
    private readonly DispatcherQueueTimer _exitSlopCommitTimer;

    internal SettingsTab()
    {
        InitializeComponent();

        // DependencyObject.DispatcherQueue, not DispatcherQueue.GetForCurrentThread() --
        // see NoteEditorHost's own constructor remarks for why the static call is ambiguous
        // here.
        _edgeDwellCommitTimer = CreateCommitTimer(() => _appStateRepository?.SetEdgeDwell(EdgeDwellSlider.Value));
        _exitDwellCommitTimer = CreateCommitTimer(() => _appStateRepository?.SetExitDwell(ExitDwellSlider.Value));
        _exitSlopCommitTimer = CreateCommitTimer(() => _appStateRepository?.SetExitSlop(ExitSlopSlider.Value));
    }

    private DispatcherQueueTimer CreateCommitTimer(Action commit)
    {
        var timer = DispatcherQueue.CreateTimer();
        timer.IsRepeating = false;
        timer.Interval = SliderCommitDelay;
        timer.Tick += (_, _) => commit();
        return timer;
    }

    /// <summary>Restarts a one-shot commit timer -- Stop() before Start() so a timer already
    /// running (mid-drag) gets its delay window pushed out again rather than firing on
    /// schedule and then firing again from this call.</summary>
    private static void RestartCommitTimer(DispatcherQueueTimer timer)
    {
        timer.Stop();
        timer.Start();
    }

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
        if (_initializing) return;
        // Live and unthrottled: PanelController reads this on every effect, so the panel
        // feels the new delay on its very next dwell, not after the debounce below settles.
        Notebar.App.Settings.EdgeDwell = e.NewValue;
        UpdateSliderLabels();
        if (_appStateRepository is not null) RestartCommitTimer(_edgeDwellCommitTimer);
    }

    private void OnExitDwellChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_initializing) return;
        Notebar.App.Settings.ExitDwell = e.NewValue;
        UpdateSliderLabels();
        if (_appStateRepository is not null) RestartCommitTimer(_exitDwellCommitTimer);
    }

    private void OnExitSlopChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_initializing) return;
        Notebar.App.Settings.ExitSlop = e.NewValue;
        UpdateSliderLabels();
        if (_appStateRepository is not null) RestartCommitTimer(_exitSlopCommitTimer);
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
