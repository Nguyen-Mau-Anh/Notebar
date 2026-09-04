using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using Notebar.App.Editor;
using Notebar.App.Panel;
using Notebar.Core.Models;
using Notebar.Core.Repositories;
using Notebar.Store;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Notebar.App.Features.Notes;

/// <summary>Hosts the WebView2-backed note editor and is the host half of its
/// bridge: persistence, focus, keystrokes, chip clicks, and pasted
/// images.</summary>
/// <remarks>
/// The editor itself is ordinary HTML — chips, checkboxes, lists and images
/// need no custom rendering the way the macOS NSTextView build did. The
/// bridge is the hard part, because the panel's collapse policy depends on
/// two facts that live inside the WebView: whether the editor has focus, and
/// when the user last typed.
///
/// <para>
/// <b>Focus is re-derived, never a stored flag alone.</b> The macOS build
/// shipped a version that trusted focus events by themselves; when a focused
/// editor was destroyed, no blur event ever arrived, the flag stuck true, and
/// the panel could not be collapsed without quitting. A WebView makes this
/// worse, not better — a renderer that crashes or navigates away also sends
/// no blur. So <see cref="HasFocus"/> is a cached value fed from three
/// independent sources: the guest's own focus/blur messages (immediate), a
/// poll of <c>notebar.hasFocus()</c> every <see cref="FocusPollInterval"/>
/// (the backstop for an event that never arrives), and
/// <see cref="CoreWebView2.ProcessFailed"/> plus navigating away, both of
/// which force it false. When in doubt this reports not focused: a panel
/// that collapses a beat early is a small annoyance, one that can never
/// collapse again is a defect that used to require quitting the app.
/// </para>
/// </remarks>
internal sealed partial class NoteEditorHost : UserControl
{
    private const string Origin = "https://notebar.local";
    private const string EditorUrl = Origin + "/editor.html";
    private const string AssetPrefix = "/asset/";
    private const uint MaxImageEdge = 2000;
    private static readonly TimeSpan FocusPollInterval = TimeSpan.FromMilliseconds(250);

    // A stored attachment's mime_type is trusted enough to read back and
    // downscale, but not enough to interpolate verbatim into a response
    // header: restrict it to what this editor ever writes there, and fall
    // back rather than let a malformed stored value inject a header.
    private static readonly HashSet<string> AllowedAttachmentMimeTypes =
        new(StringComparer.OrdinalIgnoreCase) { "image/png", "image/jpeg", "image/gif", "image/webp" };

    private readonly INoteRepository _noteRepository;
    private readonly IAttachmentRepository _attachmentRepository;
    private readonly PanelController _panelController;
    private readonly DispatcherQueueTimer _focusPollTimer;

    private Note? _note;

    // Bumped in LoadAsync, before the guest is told to load the new note,
    // and stamped by editor.js on every message it posts back. A message
    // whose generation doesn't match this is one the guest built against a
    // note we have already navigated away from — most dangerously, a
    // debounced "change" save still in flight when the switch happened,
    // which would otherwise overwrite the new note's body with the old
    // one's and then, via DeleteUnreferenced, delete every image the new
    // note actually references because the stale html doesn't mention
    // them. Cancelling the guest's save timer in setContent narrows this
    // window; this closes it, because ExecuteScriptAsync is an async round
    // trip and the guest's timer can fire before that call lands.
    private int _generation;
    private Task? _initialization;
    private volatile bool _hasFocus;

    /// <summary>Raised after a change message has been persisted, with the id
    /// of the note that was saved, the html that was saved, and the
    /// plain-text shadow derived from it (id, html, plain).</summary>
    /// <remarks>
    /// Carries the id explicitly rather than leaving the caller to infer
    /// "whichever note is active right now": LoadAsync flushes the outgoing
    /// note's pending save BEFORE switching this host's own notion of the
    /// active note, so a Task 12 caller reacting to this event while a
    /// switch is in flight would otherwise attribute the flushed note's
    /// content to the note being switched to.
    /// </remarks>
    internal event Action<string, string, string>? ContentChanged;

    /// <summary>Raised when the user clicks a notebar:// link chip (url). The
    /// host (not the WebView) owns what happens next — switching tabs,
    /// opening the task sheet — which is exactly why the guest never
    /// navigates itself.</summary>
    internal event Action<string>? ChipClicked;

    /// <summary>Raised after a pasted image has been stored as an attachment
    /// and substituted into the document (data, mime).</summary>
    internal event Action<byte[], string>? ImagePasted;

    /// <summary>See the class remarks: re-derived from three independent
    /// sources, never a single stored flag.</summary>
    internal bool HasFocus => _hasFocus;

    internal NoteEditorHost(
        INoteRepository noteRepository,
        IAttachmentRepository attachmentRepository,
        PanelController panelController)
    {
        InitializeComponent();

        _noteRepository = noteRepository;
        _attachmentRepository = attachmentRepository;
        _panelController = panelController;

        // Asked fresh by the reducer on every Send, never cached by
        // PanelController itself — see PanelController.IsEditorFocusedProvider's
        // own remarks for why. HasFocus above is this class's side of that
        // contract: always safe to read, never a flag someone forgot to clear.
        _panelController.IsEditorFocusedProvider = () => HasFocus;

        // DependencyObject.DispatcherQueue (the WinUI 3 replacement for
        // UWP's DependencyObject.Dispatcher) rather than
        // DispatcherQueue.GetForCurrentThread(): the latter's static method
        // call is ambiguous against the inherited instance property of the
        // same name from inside a DependencyObject-derived class.
        _focusPollTimer = DispatcherQueue.CreateTimer();
        _focusPollTimer.IsRepeating = true;
        _focusPollTimer.Interval = FocusPollInterval;
        _focusPollTimer.Tick += async (_, _) => await RefreshFocusAsync();

        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e) => _focusPollTimer.Start();

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        // A WebView torn down while the editor still reads as "focused" is
        // exactly the crash-with-no-blur case described in the class
        // remarks: force it false on the way out rather than trusting an
        // event that may never come.
        _hasFocus = false;
        _focusPollTimer.Stop();
    }

    /// <summary>Loads a note's body into the editor, initializing the
    /// WebView2 on first use.</summary>
    internal async Task LoadAsync(Note note)
    {
        // Flush the outgoing note BEFORE switching. Clearing the guest's
        // pending timer in setContent is what stops a stale save landing on
        // the wrong note (fix round 1) — but on its own that just discards
        // the last edits to the note being left, trading corruption for
        // silent loss. Both halves are needed: flush what is pending, then
        // invalidate anything still in flight. Reads _note, so it must run
        // before _note is reassigned below. On the very first call
        // _initialization hasn't started, so this is a guarded no-op.
        await FlushPendingSaveAsync();

        _note = note;
        _generation++;
        await EnsureInitializedAsync();
        await CallAsync("notebar.setContent", note.BodyHtml, _generation);
    }

    /// <summary>Runs a rich-text command (bold, insertUnorderedList, formatBlock
    /// with "h1", ...) against the current selection.</summary>
    internal async Task ExecCommandAsync(string command, string? value)
    {
        await EnsureInitializedAsync();
        await CallAsync("notebar.exec", command, value);
    }

    /// <summary>Sets the document root's data-theme. Never a media query on
    /// the guest side — the panel's theme is the app's own Settings value,
    /// not the browser's guess at the OS theme.</summary>
    internal async Task SetThemeAsync(string theme)
    {
        await EnsureInitializedAsync();
        await CallAsync("notebar.setTheme", theme);
    }

    /// <summary>Moves keyboard focus into the editor. Screen spec §4.1: a new
    /// note gets text-input focus immediately, the zero-friction-capture
    /// path the product exists for. Deliberately not called on every tab
    /// switch — PanelWindow.ShowWithoutActivating's whole point is that
    /// hovering the panel open never steals focus from whatever the user
    /// was doing elsewhere, and forcing focus on a switch the user didn't
    /// explicitly ask for would undercut that.</summary>
    internal void FocusEditor() => WebView.Focus(FocusState.Programmatic);

    /// <summary>Reads the guest's current content directly and saves it
    /// immediately, bypassing editor.js's 400ms debounce.</summary>
    /// <remarks>
    /// App.xaml.cs (Task 9) already carries a named seam,
    /// <c>App.FlushPendingNoteSave</c>, specifically for this: a save still
    /// waiting out its debounce when the user quits must not be lost, the
    /// same rule the macOS build followed. Wiring that seam to this method
    /// is not this task's to do — App.xaml.cs is outside Task 10's file
    /// list, and nothing constructs a NoteEditorHost yet for it to wire to —
    /// but this is the mechanism whichever task does that wiring needs. Note
    /// for whoever does: <c>Quit()</c> currently calls
    /// <c>Environment.Exit(0)</c> right after invoking the (synchronous)
    /// <c>Action</c> seam, so it will need to become awaitable for a flush
    /// through here to actually complete before the process ends.
    /// </remarks>
    internal async Task FlushPendingSaveAsync()
    {
        if (_initialization is not { IsCompletedSuccessfully: true }) return;

        try
        {
            // ExecuteScriptAsync's result is always the JSON encoding of the
            // JS expression's value; getContent() returns a string, so this
            // is a JSON string literal that has to be decoded back to raw
            // HTML.
            string encoded = await WebView.CoreWebView2.ExecuteScriptAsync("notebar.getContent()");
            SaveChange(JsonSerializer.Deserialize<string>(encoded) ?? "");
        }
        catch (Exception)
        {
            // LoadAsync calls this on every note switch now (fix round 2),
            // not only on quit — a renderer that just failed must not turn
            // a tab switch into an unhandled exception. Best effort: skip
            // the flush rather than crash. The generation guard already
            // protects the note being switched to either way.
        }
    }

    // --- setup ---

    /// <summary>Coalesces overlapping callers onto the same initialization
    /// rather than a bool guard: two LoadAsync calls racing before the first
    /// WebView2 init completes would otherwise double-subscribe every event
    /// handler on CoreWebView2 (each guest message then double-saving,
    /// double-executing every host->guest call, ...).</summary>
    private Task EnsureInitializedAsync() => _initialization ??= InitializeCoreAsync();

    private async Task InitializeCoreAsync()
    {
        await WebView.EnsureCoreWebView2Async();
        CoreWebView2 core = WebView.CoreWebView2;

        // Locked down: this is a note editor, not a browser. DevTools and the
        // context menu are attacker surface with nothing behind them worth
        // debugging in the field; zoom and the browser accelerator keys
        // (Ctrl+F, Ctrl+P, ...) belong to whatever the user is doing outside
        // a docked panel, not inside it.
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsZoomControlEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;

        // A virtual host, not file://: file:// gives the document no stable
        // origin and breaks window.chrome.webview.postMessage outright.
        string editorFolder = Path.Combine(AppContext.BaseDirectory, "Editor");
        core.SetVirtualHostNameToFolderMapping(
            "notebar.local", editorFolder, CoreWebView2HostResourceAccessKind.Allow);

        // Attachments are served through this filter rather than a custom
        // scheme, precisely so WebResourceRequested hands back a plain
        // request/response pair instead of something bespoke.
        core.AddWebResourceRequestedFilter(Origin + AssetPrefix + "*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += OnWebResourceRequested;

        core.WebMessageReceived += OnWebMessageReceived;
        core.NewWindowRequested += OnNewWindowRequested;
        core.NavigationStarting += OnNavigationStarting;
        core.ProcessFailed += OnProcessFailed;

        var navigated = new TaskCompletionSource();
        void OnNavigationCompleted(CoreWebView2 s, CoreWebView2NavigationCompletedEventArgs e) =>
            navigated.TrySetResult();
        core.NavigationCompleted += OnNavigationCompleted;
        core.Navigate(EditorUrl);
        await navigated.Task;
        core.NavigationCompleted -= OnNavigationCompleted;
    }

    // --- guest -> host ---

    private void OnWebMessageReceived(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        string raw;
        try
        {
            raw = e.TryGetWebMessageAsString();
        }
        catch (Exception)
        {
            // Not a string message — editor.js only ever posts JSON.stringify
            // output, so this should not happen, but a malformed guest
            // message is a bridge bug, not something worth crashing the host
            // process over.
            return;
        }

        EditorMessage? message = EditorMessage.Parse(raw);
        if (message is null) return;

        // See _generation's remarks: a message built against a note we have
        // already navigated away from must never be acted on, above all a
        // stale "change" or "image" that would otherwise save or attach
        // content onto the wrong note. int? != int is false only when both
        // sides match, so a missing generation (message.Generation is null)
        // is treated the same as a mismatch.
        if (message.Generation != _generation) return;

        switch (message.Type)
        {
            case EditorMessage.Focus:
                _hasFocus = message.Focused ?? false;
                break;

            case EditorMessage.Keystroke:
                // Without this, the typing-grace period never engages and
                // the panel collapses on someone mid-sentence — the single
                // worst failure mode this panel can have.
                _panelController.NoteKeystroke();
                break;

            case EditorMessage.Change:
                if (message.Html is not null) SaveChange(message.Html);
                break;

            case EditorMessage.Chip:
                if (message.Url is not null) ChipClicked?.Invoke(message.Url);
                break;

            case EditorMessage.Image:
                if (message.DataUrl is not null) _ = HandleImageAsync(message.DataUrl);
                break;
        }
    }

    /// <summary>Persists a change message. body_plain is derived here, never
    /// by the guest: it is what FTS indexes, and the store is the one that
    /// gets to decide what gets indexed.</summary>
    private void SaveChange(string html)
    {
        if (_note is null) return;

        string plain = NoteHtml.ToPlainText(html);
        _note = _note with { BodyHtml = html, BodyPlain = plain };
        _noteRepository.Update(_note);
        _attachmentRepository.DeleteUnreferenced(ExtractAssetIds(html));

        ContentChanged?.Invoke(_note.Id, html, plain);
    }

    private static IReadOnlySet<string> ExtractAssetIds(string html)
    {
        var ids = new HashSet<string>();
        foreach (Match match in AssetUrlPattern().Matches(html))
            ids.Add(match.Groups[1].Value);
        return ids;
    }

    [GeneratedRegex(@"https://notebar\.local/asset/([A-Za-z0-9-]+)")]
    private static partial Regex AssetUrlPattern();

    private async Task HandleImageAsync(string dataUrl)
    {
        try
        {
            var (mime, bytes) = DecodeDataUrl(dataUrl);
            var (data, width, height) = await DownscaleIfNeededAsync(bytes);
            Attachment attachment = _attachmentRepository.Create(mime, data, width, height);

            string html = $"<img src=\"{Origin}{AssetPrefix}{attachment.Id}\">";
            await CallAsync("notebar.insertHtml", html);

            ImagePasted?.Invoke(data, mime);
        }
        catch (Exception)
        {
            // A malformed data URL, or an image WinRT's decoder cannot read.
            // Dropping the paste is the right failure: the user's typed text
            // in the note is untouched either way.
        }
    }

    private static (string Mime, byte[] Bytes) DecodeDataUrl(string dataUrl)
    {
        int comma = dataUrl.IndexOf(',');
        if (comma < 0) throw new FormatException("not a data: URL");

        string header = dataUrl[..comma];
        int semicolon = header.IndexOf(';');
        string mime = semicolon > "data:".Length ? header["data:".Length..semicolon] : "application/octet-stream";
        byte[] bytes = Convert.FromBase64String(dataUrl[(comma + 1)..]);
        return (mime, bytes);
    }

    /// <summary>Downscales so the longest edge is at most
    /// <see cref="MaxImageEdge"/> px, preserving the source's own container
    /// format. Returns the bytes unchanged when already within bounds.</summary>
    private static async Task<(byte[] Data, int Width, int Height)> DownscaleIfNeededAsync(byte[] bytes)
    {
        using IRandomAccessStream input = new MemoryStream(bytes).AsRandomAccessStream();
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(input);
        uint width = decoder.PixelWidth;
        uint height = decoder.PixelHeight;
        uint longestEdge = Math.Max(width, height);

        if (longestEdge <= MaxImageEdge)
            return (bytes, (int)width, (int)height);

        double scale = (double)MaxImageEdge / longestEdge;
        uint newWidth = (uint)Math.Max(1, Math.Round(width * scale));
        uint newHeight = (uint)Math.Max(1, Math.Round(height * scale));

        using var output = new InMemoryRandomAccessStream();
        BitmapEncoder encoder = await BitmapEncoder.CreateForTranscodingAsync(output, decoder);
        encoder.BitmapTransform.ScaledWidth = newWidth;
        encoder.BitmapTransform.ScaledHeight = newHeight;
        encoder.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
        await encoder.FlushAsync();

        var buffer = new byte[output.Size];
        output.Seek(0);
        await output.ReadAsync(buffer.AsBuffer(), (uint)buffer.Length, InputStreamOptions.None);
        return (buffer, (int)newWidth, (int)newHeight);
    }

    // --- host -> guest ---

    /// <summary>Builds and runs <c>notebar.&lt;function&gt;(arg1, arg2, ...)</c>,
    /// JSON-encoding every string argument so a note body containing a quote
    /// or a backslash can never break out of the generated script. Ints
    /// (e.g. the generation stamp) are emitted as raw numeric literals, not
    /// quoted — the guest reads them back as numbers, not strings.</summary>
    private async Task CallAsync(string function, params object?[] args)
    {
        string call = $"{function}({string.Join(", ", args.Select(EncodeArg))})";
        await WebView.CoreWebView2.ExecuteScriptAsync(call);
    }

    private static string EncodeArg(object? arg) => arg switch
    {
        null => "null",
        int i => i.ToString(System.Globalization.CultureInfo.InvariantCulture),
        string s => JsonSerializer.Serialize(s),
        _ => JsonSerializer.Serialize(arg),
    };

    private async Task RefreshFocusAsync()
    {
        if (_initialization is not { IsCompletedSuccessfully: true }) return;
        try
        {
            string result = await WebView.CoreWebView2.ExecuteScriptAsync("notebar.hasFocus()");
            _hasFocus = result == "true";
        }
        catch (Exception)
        {
            // The WebView can be mid-navigation or mid-teardown when this
            // fires; an unreadable focus state is not a focused one.
            _hasFocus = false;
        }
    }

    // --- WebView2 event handlers ---

    private void OnWebResourceRequested(CoreWebView2 sender, CoreWebView2WebResourceRequestedEventArgs e)
    {
        string path = new Uri(e.Request.Uri).AbsolutePath;
        if (!path.StartsWith(AssetPrefix, StringComparison.Ordinal)) return;

        string id = path[AssetPrefix.Length..];
        Attachment? attachment = _attachmentRepository.Fetch(id);
        if (attachment is null)
        {
            e.Response = sender.Environment.CreateWebResourceResponse(null, 404, "Not Found", "");
            return;
        }

        // The stored value is trusted enough to read back, not enough to
        // interpolate verbatim into a response header: a malformed row
        // (however it got that way) must not be able to inject one.
        string mime = AllowedAttachmentMimeTypes.Contains(attachment.MimeType)
            ? attachment.MimeType
            : "application/octet-stream";

        IRandomAccessStream stream = new MemoryStream(attachment.Data).AsRandomAccessStream();
        e.Response = sender.Environment.CreateWebResourceResponse(
            stream, 200, "OK", $"Content-Type: {mime}");
    }

    private static void OnNewWindowRequested(CoreWebView2 sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        // A note body can carry a pasted external link; a popup WebView
        // inside the panel would be both ugly and a security surprise. Hand
        // it to the user's own default browser instead.
        e.Handled = true;
        _ = Windows.System.Launcher.LaunchUriAsync(new Uri(e.Uri));
    }

    private void OnNavigationStarting(CoreWebView2 sender, CoreWebView2NavigationStartingEventArgs e)
    {
        // A navigation away from the editor document sends no blur from the
        // guest. If in doubt, report not focused.
        _hasFocus = false;
    }

    private void OnProcessFailed(CoreWebView2 sender, CoreWebView2ProcessFailedEventArgs e)
    {
        // A crashed or unresponsive renderer sends no blur either. Same rule.
        _hasFocus = false;
    }
}
