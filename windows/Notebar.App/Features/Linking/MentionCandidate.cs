using Notebar.Core.Models;

namespace Notebar.App.Features.Linking;

/// <summary>One row the @ mention popover or the backlinks list can show -- a note or a
/// task, projected down to exactly what a row needs to render and what selecting it needs
/// to build a chip (id, type, title, an "updated" timestamp for sorting/display). Mirrors
/// the macOS build's MentionCandidate (NoteMentionAutocomplete.swift); shared here by both
/// Task 15 surfaces instead of each defining its own near-identical projection.</summary>
internal sealed record MentionCandidate(LinkEntityType Type, string Id, string Title, DateTimeOffset UpdatedAt)
{
    /// <summary>Mirrors Note.DisplayTitle / NoteSummary.DisplayTitle exactly -- an untitled
    /// note must read the same way here as it does in the tab strip and the all-notes
    /// menu.</summary>
    internal string DisplayTitle => string.IsNullOrEmpty(Title) ? "Untitled" : Title;

    /// <summary>Segoe Fluent glyph codepoints already in use elsewhere in this codebase
    /// (NotesTab's own toolbar buttons use 0xE8A5/0xE70D as FontIcon glyphs) -- 0xE8A5 is
    /// the "document" glyph for a note target, 0xE73A a checkmark for a task target,
    /// mirroring the macOS build's doc.text/checklist SF Symbol pairing for the identical
    /// distinction. Built from the raw codepoint via (char) rather than a string literal
    /// containing the glyph itself, so this source file stays plain ASCII and cannot fall
    /// victim to an editor/encoding round trip silently mangling a private-use codepoint.</summary>
    internal string TypeGlyph => ((char)(Type == LinkEntityType.Note ? 0xE8A5 : 0xE73A)).ToString();
}
