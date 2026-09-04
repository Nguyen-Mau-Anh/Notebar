using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace Notebar.Store;

/// <summary>Derives a note's plain-text shadow from its HTML body.</summary>
/// <remarks>
/// This is what FTS5 indexes, and what Note.IsEmptyAndUntitled inspects, so it
/// must produce the text a user would say is in the note and nothing else. List
/// markers and checkbox glyphs are excluded deliberately: they are editor
/// bookkeeping, and indexing them would make every checklist match a search for
/// a glyph nobody typed.
///
/// A regex rather than an HTML parser because the input is not arbitrary web
/// HTML — it is the markup this app's own editor produced, from a fixed set of
/// tags. A parser dependency would buy robustness against input that cannot
/// occur.
/// </remarks>
public static partial class NoteHtml
{
    public static string ToPlainText(string html)
    {
        if (string.IsNullOrEmpty(html)) return "";

        // Drop elements whose content is not text at all, content included.
        string s = NonTextElements().Replace(html, "");

        // Block boundaries become line breaks before tags are stripped, so
        // "<p>one</p><p>two</p>" does not collapse into "onetwo".
        s = BlockBoundaries().Replace(s, "\n");

        s = Tags().Replace(s, "");
        s = WebUtility.HtmlDecode(s);

        // Collapse runs of horizontal whitespace, trim each line, drop blank
        // lines. An untouched editor's "<p><br></p>" must end up as "".
        var lines = s.Split('\n')
                     .Select(line => HorizontalWhitespace().Replace(line, " ").Trim())
                     .Where(line => line.Length > 0);

        return string.Join("\n", lines);
    }

    [GeneratedRegex(@"<(script|style)\b[^>]*>.*?</\1\s*>",
        RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex NonTextElements();

    [GeneratedRegex(@"</?(p|div|li|ul|ol|h1|h2|h3|br|tr|blockquote|pre)\b[^>]*>",
        RegexOptions.IgnoreCase)]
    private static partial Regex BlockBoundaries();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex Tags();

    [GeneratedRegex(@"[^\S\n]+")]
    private static partial Regex HorizontalWhitespace();
}
