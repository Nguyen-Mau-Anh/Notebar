namespace Notebar.Store;

/// <summary>Turns whatever the user typed into something FTS5 will accept.</summary>
/// <remarks>
/// FTS5's MATCH grammar treats quotes, asterisks, parentheses, colons, and bare
/// AND/OR/NOT as syntax. A user typing a quote into the search box should get no
/// results, not a SqliteException — so every token is quoted as a literal and
/// given a trailing * for prefix matching, which is what a search-as-you-type box
/// needs anyway.
/// </remarks>
public static class FtsQuery
{
    public static string Sanitize(string query)
    {
        var tokens = query
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Select(t => new string(t.Where(char.IsLetterOrDigit).ToArray()))
            .Where(t => t.Length > 0)
            .Select(t => $"\"{t}\"*");

        return string.Join(" ", tokens);
    }
}
