using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Notebar.App.Interop;
using Notebar.App.Panel;
using Notebar.Core.Geometry;
using Notebar.Core.Panel;
using Notebar.Core.Repositories;
using Notebar.Store;

namespace Notebar.App;

public partial class App : Application
{
    /// <summary>How long Quit waits for FlushPendingNoteSave before giving up
    /// and exiting anyway. A save that cannot complete within this window
    /// (a wedged WebView2 renderer, most plausibly) must not be able to
    /// leave the app unquittable — a bounded loss of the last keystrokes is
    /// a smaller harm than an app the user can no longer close.</summary>
    private static readonly TimeSpan FlushTimeout = TimeSpan.FromSeconds(3);

    private PanelWindow? _window;
    private CursorMonitor? _cursorMonitor;
    private PanelController? _panelController;
    private MessageWindow? _messageWindow;
    private TrayIcon? _trayIcon;
    private GlobalHotKey? _hotKey;
    private NotebarDatabase? _database;

    /// <summary>The one PanelController for the app's lifetime. Later tasks —
    /// the note editor reporting keystrokes and focus, the tray icon's toggle,
    /// a drag source setting IsDragging — reach it through here rather than
    /// each holding their own reference.</summary>
    internal PanelController? PanelController => _panelController;

    /// <summary>Set by NotesTab (Task 12), once it has constructed the one
    /// NoteEditorHost, to flush any save still waiting out its debounce.
    /// Awaited by Quit, bounded by FlushTimeout, before anything else is
    /// torn down — a fire-and-forget Action here was the macOS build's own
    /// bug before it was fixed: the flush racing process exit and losing.
    /// There is nothing to set this before AttachController runs, so it is
    /// a named seam rather than a TODO for the time in between.</summary>
    internal Func<Task>? FlushPendingNoteSave { get; set; }

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var window = new PanelWindow();
        _window = window;

        var cursor = NativeMethods.GetCursorPos(out var pt)
            ? new PanelPoint(pt.X, pt.Y)
            : new PanelPoint(0, 0);
        var workArea = MonitorInfo.WorkAreaContaining(cursor, out double scale);
        var workAreaDips = new PanelRect(
            workArea.X / scale, workArea.Y / scale,
            workArea.Width / scale, workArea.Height / scale);

        window.ApplyFrame(PanelGeometry.Collapsed(workAreaDips), scale);
        window.ShowWithoutActivating();

        // Task 12: the one database this app opens. %LOCALAPPDATA%\Notebar —
        // the conventional per-user, non-roaming location for an app's own
        // data on Windows. A locked, corrupt, or otherwise inaccessible file
        // must not stop the panel from showing at all: OpenInMemory is the
        // same degrade path NotebarDatabase already documents for tests,
        // pressed into service here so a bad database file costs the user a
        // session of persistence rather than the app failing to launch.
        string dbPath = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Notebar", "notebar.sqlite");
        NotebarDatabase database;
        try
        {
            database = NotebarDatabase.Open(dbPath);
        }
        catch (Exception)
        {
            database = NotebarDatabase.OpenInMemory();
        }
        _database = database;

        INoteRepository noteRepository = new SqliteNoteRepository(database);
        IOpenTabRepository openTabRepository = new SqliteOpenTabRepository(database);
        IAttachmentRepository attachmentRepository = new SqliteAttachmentRepository(database);
        // Task 14: the tasks board's repository -- its three columns are seeded by
        // migration, same as the note/open-tab/attachment tables above.
        ITaskRepository taskRepository = new SqliteTaskRepository(database);

        // Held for the app's lifetime, not scoped to OnLaunched: the controller
        // owns the panel's whole state machine, and the monitor is the only
        // thing driving it. Neither Activate()s the window — hovering must never
        // steal focus, and PanelWindow.ShowWithoutActivating already handles
        // showing it without doing so.
        var queue = DispatcherQueue.GetForCurrentThread();
        var cursorMonitor = new CursorMonitor(queue);
        _cursorMonitor = cursorMonitor;
        var panelController = new PanelController(window, cursorMonitor, queue);
        _panelController = panelController;
        cursorMonitor.Start();

        // Task 11's shell chrome (RootPage/TabRail/TabToolbar) needs a live PanelController
        // to build PanelViewModel against -- e.g. the pin and maximize toggles write straight
        // into it from their own property setters (see PanelViewModel's remarks on why that
        // ordering is what fixes the one-click-behind defect the macOS pin toggle shipped
        // with). RootPage exists already (PanelWindow's constructor built it via
        // InitializeComponent above), but the controller wrapping this same window could not
        // exist before this point, so this is the earliest this wiring can happen.
        window.AttachController(panelController, noteRepository, openTabRepository, attachmentRepository, taskRepository);

        // One hidden window backs both the tray callback and the global
        // hotkey — see MessageWindow's remarks for why a second window
        // would be redundant. Local variables throughout this block, not the
        // nullable fields, so every downstream use here is provably non-null
        // rather than depending on the compiler's flow analysis of a field
        // read back out of a closure.
        var messageWindow = new MessageWindow();
        _messageWindow = messageWindow;

        var trayIcon = new TrayIcon(messageWindow, panelController, ShowSettings, Quit);
        _trayIcon = trayIcon;
        trayIcon.Show();

        var hotKey = new GlobalHotKey(messageWindow);
        _hotKey = hotKey;
        hotKey.Pressed += () => panelController.Send(PanelEvent.ToggleRequested);
        if (!hotKey.TryRegister())
        {
            // Common — another app already holds Ctrl+Shift+N — and not the
            // user's fault. Task 16's Settings will surface this as "the
            // shortcut is unavailable"; there is nowhere to surface it yet,
            // so this stays a non-fatal no-op rather than a crash or a
            // silently-broken shortcut nobody is told about.
        }
    }

    /// <summary>Opens Settings. A stub until Task 16 builds the window — the
    /// tray menu's "Settings" entry exists now so it never has to move.</summary>
    private void ShowSettings()
    {
    }

    /// <summary>Flushes any pending note save, removes the tray icon, then
    /// exits. Order matters: the flush must run before anything else can
    /// interrupt it, and the tray icon must be gone before the process ends —
    /// an orphaned tray icon that outlives its process is a well-known
    /// Windows annoyance the user has to hover away.</summary>
    /// <remarks>
    /// This is the reachable way to quit that does not depend on the tray
    /// icon being visible — the same rule macOS follows, where the menu bar
    /// item can be hidden by the notch. Task 16's Settings window calls this
    /// too, once it exists.
    ///
    /// <para>
    /// A plain synchronous <c>void</c> method — TrayIcon's menu callback and
    /// GlobalHotKey both expect a bare <c>Action</c> — that fires QuitAsync
    /// and returns immediately. The process does not actually end until
    /// QuitAsync's own Environment.Exit(0) runs; the WinUI message loop is
    /// still pumping in the meantime, which is what lets the awaited flush
    /// below actually make progress.
    /// </para>
    /// </remarks>
    internal void Quit() => _ = QuitAsync();

    /// <summary>The awaitable half of Quit. FlushPendingNoteSave is a
    /// <c>Func&lt;Task&gt;</c>, not a fire-and-forget <c>Action</c>,
    /// specifically so this can await it before anything else runs — wiring
    /// an async save to a synchronous seam is exactly the bug that let the
    /// flush race process exit and lose on macOS before that was fixed
    /// there. Bounded by FlushTimeout: a save that throws is caught here
    /// (NoteEditorHost.FlushPendingSaveAsync already catches its own, but
    /// nothing upstream should have to trust that), and a save that never
    /// completes at all must not be able to hang the app open forever.
    /// </summary>
    private async Task QuitAsync()
    {
        if (FlushPendingNoteSave is { } flush)
        {
            try
            {
                await Task.WhenAny(flush(), Task.Delay(FlushTimeout));
            }
            catch (Exception)
            {
                // Best-effort: a broken flush must not stop the app from
                // quitting.
            }
        }

        _trayIcon?.Dispose();
        _hotKey?.Dispose();
        _messageWindow?.Dispose();
        _database?.Dispose();

        // Exit() gives WinUI a chance to run its own shutdown notifications;
        // Environment.Exit is the backstop that actually ends the process
        // regardless of what state the hidden PanelWindow or any timer is
        // in — this app has no "last window closed" to rely on, since the
        // panel window is hidden, not closed, for its entire life.
        Exit();
        Environment.Exit(0);
    }
}
