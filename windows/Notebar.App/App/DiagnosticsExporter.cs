using Notebar.App.Panel;
using Notebar.Core.Models;
using Notebar.Core.Repositories;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Notebar.App;

/// <summary>Settings -> Data's *Export Diagnostics* button: collects an
/// environment block (app version, Windows version, display geometry,
/// database path/size/migrations) plus a recent log excerpt, and writes one
/// file the user picks the location for.</summary>
/// <remarks>
/// Mirrors macOS's <c>DiagnosticsExporter</c>: the environment block is built
/// by <see cref="DiagnosticsEnvironment"/> (Notebar.Core), a pure type with no
/// room for note or task content in its fields -- this type only ever fills
/// those fields in and appends <see cref="NotebarLog"/>'s excerpt as
/// unstructured text alongside it. See
/// <c>DiagnosticsExportContentTests</c> in Notebar.Store.Tests for the test
/// that leans on that structural guarantee against the real repository call
/// path, and <c>DiagnosticsTests</c> in Notebar.Core.Tests for the type-level
/// proof.
///
/// <para>Lives in the app project, not Notebar.Core/Notebar.Store: it needs
/// <c>FileSavePicker</c> and the owning window's handle, neither of which
/// belongs in either package.</para>
/// </remarks>
internal static class DiagnosticsExporter
{
    /// <summary>Presents a save picker and, if the user picks a location,
    /// writes the diagnostics file there. Never writes anywhere without the
    /// user choosing the location first.</summary>
    internal static async Task ExportAsync(IntPtr ownerHwnd, IDiagnosticsRepository diagnosticsRepository)
    {
        string text = BuildReport(diagnosticsRepository);

        var picker = new FileSavePicker();
        // FileSavePicker needs an owning window in an unpackaged/desktop
        // WinUI 3 app -- the same IInitializeWithWindow dance PanelWindow's
        // own constructor already does for WindowNative.GetWindowHandle,
        // just in the other direction.
        InitializeWithWindow.Initialize(picker, ownerHwnd);
        picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
        picker.SuggestedFileName = "Notebar Diagnostics";
        picker.FileTypeChoices.Add("Plain Text", new List<string> { ".txt" });

        StorageFile? file = await picker.PickSaveFileAsync();
        if (file is null) return; // cancelled

        try
        {
            await FileIO.WriteTextAsync(file, text);
            NotebarLog.Info("diagnostics exported");
        }
        catch (Exception ex)
        {
            NotebarLog.Error($"failed to write diagnostics export: {ex.GetType().Name}: {ex.Message}");
        }
    }

    private static string BuildReport(IDiagnosticsRepository diagnosticsRepository)
    {
        var environment = new DiagnosticsEnvironment(
            AppVersion.ShortVersion,
            AppVersion.BuildNumber,
            Environment.OSVersion.VersionString,
            MonitorInfo.DescribeCursorMonitor(),
            diagnosticsRepository.Snapshot());

        return $"""
            Notebar Diagnostics
            ====================

            {environment.RenderedText}

            Recent log (this session)
            --------------------------------------------------------------
            {NotebarLog.RenderedText()}
            """;
    }
}
