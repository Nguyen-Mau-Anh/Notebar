using System.Text.Json;
using System.Text.Json.Serialization;

namespace Notebar.App.Editor;

/// <summary>The one message envelope the guest document posts to the host, as
/// JSON — never an ad-hoc string per message kind.</summary>
/// <remarks>
/// Guest → host arrives via CoreWebView2.WebMessageReceived, always a string
/// the guest built with <c>window.chrome.webview.postMessage(JSON.stringify(...))</c>
/// (see editor.js). Host → guest goes the other way, through
/// <c>ExecuteScriptAsync</c> calling into <c>window.notebar</c> — a set of
/// plain function calls, not a matching envelope, because that side is
/// driving the guest rather than reporting something that happened in it.
///
/// Declaring every field the guest can ever send in one record, next to the
/// parser that reads it, is what keeps a message's shape and how it is read
/// from drifting apart: a field renamed on one side breaks a compile-time
/// property reference on the other, not a string it silently stops matching.
/// </remarks>
internal sealed record EditorMessage(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("html")] string? Html,
    [property: JsonPropertyName("text")] string? Text,
    [property: JsonPropertyName("url")] string? Url,
    [property: JsonPropertyName("dataUrl")] string? DataUrl)
{
    // The eight message kinds editor.js posts.
    internal const string Focus = "focus";
    internal const string Keystroke = "keystroke";
    internal const string Change = "change";
    internal const string Chip = "chip";
    internal const string Image = "image";

    /// <summary>Task 15: the guest reports the "@" mention session's live state -- opened,
    /// the query typed since, and the caret's client-coordinate rect -- so the host-side
    /// popover (host-side, not the WebView2 document, precisely so it can set
    /// PanelController.HasOpenOverlay -- see NoteEditorHost's own remarks) knows what to
    /// show and where. Open=false closes any popover the host has showing, however the
    /// guest arrived at that: whitespace typed into the query, the caret moving away, or
    /// Escape.</summary>
    internal const string Mention = "mention";

    /// <summary>Task 15: ArrowUp/ArrowDown/Enter/Tab pressed while a mention session is
    /// open, forwarded here because the popover they need to drive is host-side XAML the
    /// guest cannot reach directly -- see editor.js's own remarks on why these are
    /// intercepted with preventDefault rather than left to move the caret or insert a
    /// newline.</summary>
    internal const string MentionKey = "mentionKey";

    /// <summary>Task 13: the guest's document.queryCommandState/Value snapshot,
    /// posted on every selectionchange so the formatting bar's toggles
    /// reflect the caret rather than being decorative. Every field below is
    /// only present on this message kind.</summary>
    internal const string Styles = "styles";

    /// <summary>Only the "focus" message carries this; every other kind
    /// leaves it null.</summary>
    [JsonPropertyName("focused")]
    public bool? Focused { get; init; }

    /// <summary>The guest document's generation at the moment this message
    /// was posted (editor.js stamps every outgoing message with it). The
    /// host compares this against the generation it bumped when it last
    /// told the guest to load a note, and drops anything that doesn't
    /// match — see NoteEditorHost.OnWebMessageReceived. A message that
    /// never went through post() (i.e. this is null) is treated the same
    /// as a mismatch: if in doubt, it describes a note that is no longer
    /// current.</summary>
    [JsonPropertyName("generation")]
    public int? Generation { get; init; }

    // --- "styles" message fields (Task 13). Only editor.js's selectionchange
    // handler ever populates these; every other message kind leaves them
    // null, read as false by NoteEditorHost.OnWebMessageReceived. ---

    [JsonPropertyName("bold")]
    public bool? Bold { get; init; }

    [JsonPropertyName("italic")]
    public bool? Italic { get; init; }

    [JsonPropertyName("code")]
    public bool? Code { get; init; }

    [JsonPropertyName("heading1")]
    public bool? Heading1 { get; init; }

    [JsonPropertyName("heading2")]
    public bool? Heading2 { get; init; }

    [JsonPropertyName("bulletedList")]
    public bool? BulletedList { get; init; }

    [JsonPropertyName("numberedList")]
    public bool? NumberedList { get; init; }

    [JsonPropertyName("checklist")]
    public bool? Checklist { get; init; }

    // --- "mention" message fields (Task 15). Only editor.js's mention-session tracking
    // ever populates Open/Query/X/Y; only its mention-key interception populates Key. ---

    [JsonPropertyName("open")]
    public bool? Open { get; init; }

    [JsonPropertyName("query")]
    public string? Query { get; init; }

    [JsonPropertyName("x")]
    public double? X { get; init; }

    [JsonPropertyName("y")]
    public double? Y { get; init; }

    /// <summary>Only the "mentionKey" message carries this.</summary>
    [JsonPropertyName("key")]
    public string? Key { get; init; }

    /// <summary>Null for anything that is not a well-formed EditorMessage —
    /// a malformed message from the guest is a bridge bug, not something
    /// worth taking the host down over.</summary>
    internal static EditorMessage? Parse(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<EditorMessage>(json);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>The eight formatting states FormattingBar's buttons reflect
/// (Task 13, screen spec §4.2 / macOS's NoteTextStyle), derived from one
/// "styles" EditorMessage. A plain record rather than reusing EditorMessage
/// itself downstream of NoteEditorHost — FormattingBar should never need to
/// know about generations, JSON property names, or the other four message
/// kinds a raw EditorMessage carries.</summary>
internal sealed record EditorStyles(
    bool Bold,
    bool Italic,
    bool Code,
    bool Heading1,
    bool Heading2,
    bool BulletedList,
    bool NumberedList,
    bool Checklist)
{
    internal static EditorStyles FromMessage(EditorMessage message) => new(
        message.Bold ?? false,
        message.Italic ?? false,
        message.Code ?? false,
        message.Heading1 ?? false,
        message.Heading2 ?? false,
        message.BulletedList ?? false,
        message.NumberedList ?? false,
        message.Checklist ?? false);
}

/// <summary>Task 15: the @ mention session's live state, derived from one "mention"
/// EditorMessage -- NotesTab's mention popover reacts to this, never to a raw
/// EditorMessage, the same reason EditorStyles exists above.</summary>
internal readonly record struct MentionUpdate(bool Open, string Query, double X, double Y)
{
    internal static MentionUpdate FromMessage(EditorMessage message) => new(
        message.Open ?? false,
        message.Query ?? "",
        message.X ?? 0,
        message.Y ?? 0);
}
