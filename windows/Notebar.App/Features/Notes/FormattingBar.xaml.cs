using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Notebar.App.Editor;

namespace Notebar.App.Features.Notes;

/// <summary>The eight formatting controls beneath the tab toolbar (screen spec §4.2): Bold,
/// Italic, Code, H1, H2, Bulleted list, Numbered list, Checklist. Mirrors the macOS build's
/// FormattingBarView/NoteEditingContext split — this control owns only presentation, never
/// talks to the WebView2 directly. NotesTab wires ExecRequested/ChecklistRequested to the
/// one shared NoteEditorHost and relays NoteEditorHost.StylesChanged back into
/// SetActiveStyles, the same seam TabStrip's own events go through.</summary>
internal sealed partial class FormattingBar : UserControl
{
    /// <summary>The exact snippet the task brief specifies for the checklist button.
    /// editor.js's own markdown-shortcut handler for "[] " builds the identical string
    /// (CHECKLIST_HTML) — kept in sync by comment on both sides rather than a shared
    /// constant, since one side is C# and the other JS and nothing can straddle that
    /// boundary directly.</summary>
    internal const string ChecklistHtml = "<ul class=\"checklist\"><li><input type=\"checkbox\"> </li></ul>";

    private readonly ButtonVisual[] _visuals;

    /// <summary>Raised for the seven buttons that map to a plain document.execCommand
    /// (command, value) — value is null for the commands that take none (bold, italic, the
    /// two list commands).</summary>
    internal event Action<string, string?>? ExecRequested;

    /// <summary>Raised for the checklist button alone: there is no document.execCommand for
    /// "insert a checklist", so NotesTab routes this to NoteEditorHost.InsertHtmlAsync
    /// instead of ExecCommandAsync.</summary>
    internal event Action? ChecklistRequested;

    internal FormattingBar()
    {
        InitializeComponent();

        // Table-driven rather than eight hand-written Click/PointerEntered/PointerExited
        // methods: every button follows the exact same three behaviours (run its command,
        // show a hover tint, show an active tint), so the only thing that differs between
        // them is which four named elements and which command/value pair they carry. A
        // checklist entry (Command: null) is the one row OnClicked treats specially.
        _visuals =
        [
            new(BoldButton, BoldHoverBg, BoldActiveBg, BoldTextOff, BoldTextOn, "bold", null),
            new(ItalicButton, ItalicHoverBg, ItalicActiveBg, ItalicTextOff, ItalicTextOn, "italic", null),
            new(CodeButton, CodeHoverBg, CodeActiveBg, CodeTextOff, CodeTextOn, "formatBlock", "<pre>"),
            new(H1Button, H1HoverBg, H1ActiveBg, H1TextOff, H1TextOn, "formatBlock", "<h1>"),
            new(H2Button, H2HoverBg, H2ActiveBg, H2TextOff, H2TextOn, "formatBlock", "<h2>"),
            new(BulletButton, BulletHoverBg, BulletActiveBg, BulletTextOff, BulletTextOn, "insertUnorderedList", null),
            new(NumberButton, NumberHoverBg, NumberActiveBg, NumberTextOff, NumberTextOn, "insertOrderedList", null),
            new(ChecklistButton, ChecklistHoverBg, ChecklistActiveBg, ChecklistTextOff, ChecklistTextOn, null, null),
        ];

        foreach (ButtonVisual visual in _visuals)
        {
            visual.Button.Click += (_, _) => OnClicked(visual);
            visual.Button.PointerEntered += (_, _) => SetHover(visual, true);
            visual.Button.PointerExited += (_, _) => SetHover(visual, false);
        }
    }

    /// <summary>Called from NoteEditorHost.StylesChanged (relayed by NotesTab): reflects
    /// where the caret actually is, per the brief's "button state reflects the selection."
    /// Reassigns all eight every time rather than diffing — the guest only ever posts a
    /// complete snapshot (editor.js's selectionchange handler), never a partial update, so
    /// there is nothing to diff against.</summary>
    internal void SetActiveStyles(EditorStyles styles)
    {
        SetActive(_visuals[0], styles.Bold);
        SetActive(_visuals[1], styles.Italic);
        SetActive(_visuals[2], styles.Code);
        SetActive(_visuals[3], styles.Heading1);
        SetActive(_visuals[4], styles.Heading2);
        SetActive(_visuals[5], styles.BulletedList);
        SetActive(_visuals[6], styles.NumberedList);
        SetActive(_visuals[7], styles.Checklist);
    }

    private void OnClicked(ButtonVisual visual)
    {
        if (visual.Command is null) ChecklistRequested?.Invoke();
        else ExecRequested?.Invoke(visual.Command, visual.Value);
    }

    /// <summary>§3's hover rule, reused from TabRail: a hover tint never overrides an
    /// already-active button's background, so moving the pointer over an active button
    /// doesn't flash the weaker hover tint for a frame.</summary>
    private static void SetHover(ButtonVisual visual, bool isHovering)
    {
        if (visual.ActiveBg.Visibility == Visibility.Visible) return;
        visual.HoverBg.Visibility = isHovering ? Visibility.Visible : Visibility.Collapsed;
    }

    private static void SetActive(ButtonVisual visual, bool isActive)
    {
        visual.ActiveBg.Visibility = isActive ? Visibility.Visible : Visibility.Collapsed;
        visual.HoverBg.Visibility = Visibility.Collapsed;
        visual.TextOff.Visibility = isActive ? Visibility.Collapsed : Visibility.Visible;
        visual.TextOn.Visibility = isActive ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>One button's four named visual elements plus the command it runs.
    /// Command is null only for the checklist entry — see OnClicked. TextOff/TextOn are
    /// FrameworkElement, not TextBlock: seven buttons use a plain-text TextBlock glyph, but
    /// the checklist button uses a FontIcon (Segoe Fluent Icons) instead — see its own
    /// remarks in FormattingBar.xaml. Only Visibility is ever touched here, which both
    /// share.</summary>
    private sealed record ButtonVisual(
        Button Button,
        Border HoverBg,
        Border ActiveBg,
        FrameworkElement TextOff,
        FrameworkElement TextOn,
        string? Command,
        string? Value);
}
