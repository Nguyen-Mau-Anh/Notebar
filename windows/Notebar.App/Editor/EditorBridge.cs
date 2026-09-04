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
    // The five message kinds editor.js posts.
    internal const string Focus = "focus";
    internal const string Keystroke = "keystroke";
    internal const string Change = "change";
    internal const string Chip = "chip";
    internal const string Image = "image";

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
