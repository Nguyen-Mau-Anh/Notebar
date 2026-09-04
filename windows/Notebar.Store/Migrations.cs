using Notebar.Core.Schema;

namespace Notebar.Store;

public sealed record Migration(string Name, IReadOnlyList<string> Statements);

/// <summary>Every migration, in application order.</summary>
/// <remarks>
/// Additive only. Never edit an entry that has shipped: a database that already
/// recorded it will not run it again, so the change would apply to fresh
/// databases and not to existing ones, silently giving two users different
/// schemas. Add a new entry at the end instead.
///
/// Migration bodies containing several statements are split here rather than
/// passed to SQLite as one string, because Microsoft.Data.Sqlite executes only
/// the first statement of a multi-statement command.
/// </remarks>
public static class Migrations
{
    public static IReadOnlyList<Migration> All { get; } =
    [
        new(NoteSchema.MigrationName,
        [
            NoteSchema.CreateNoteTable,
            NoteSchema.CreateNoteFtsTable,
            .. SplitStatements(NoteSchema.NoteFtsTriggers),
        ]),
        new(OpenTabSchema.MigrationName,
        [
            OpenTabSchema.CreateOpenTabTable,
        ]),
        new(TaskSchema.MigrationName,
        [
            TaskSchema.CreateBoardTable,
            TaskSchema.CreateBoardColumnTable,
            TaskSchema.CreateTaskTable,
            TaskSchema.CreateTaskFtsTable,
            .. SplitStatements(TaskSchema.TaskFtsTriggers),
            TaskSchema.SeedBoard,
            TaskSchema.SeedColumns,
        ]),
        new(AppStateSchema.MigrationName, [AppStateSchema.CreateAppStateTable]),
        new(LinkSchema.MigrationName,
        [
            LinkSchema.CreateLinkTable,
            LinkSchema.CreateSrcIndex,
            LinkSchema.CreateDstIndex,
            LinkSchema.CascadeOnNoteDelete,
            LinkSchema.CascadeOnTaskDelete,
        ]),
        new(AttachmentSchema.MigrationName, [AttachmentSchema.CreateAttachmentTable]),
    ];

    /// <summary>Splits a script into individual statements on "END;" and ";"
    /// boundaries, keeping CREATE TRIGGER bodies intact. Trigger bodies are the
    /// only multi-statement constructs in this schema.</summary>
    internal static IReadOnlyList<string> SplitStatements(string script)
    {
        var statements = new List<string>();
        var current = new System.Text.StringBuilder();
        var inTrigger = false;

        foreach (var rawLine in script.Split('\n'))
        {
            var line = rawLine.TrimEnd();
            if (line.Length == 0) continue;
            current.AppendLine(line);

            if (line.TrimStart().StartsWith("CREATE TRIGGER", StringComparison.OrdinalIgnoreCase))
                inTrigger = true;

            bool ends = inTrigger
                ? line.Trim().Equals("END;", StringComparison.OrdinalIgnoreCase)
                : line.TrimEnd().EndsWith(';');

            if (ends)
            {
                statements.Add(current.ToString().Trim());
                current.Clear();
                inTrigger = false;
            }
        }

        if (current.Length > 0) statements.Add(current.ToString().Trim());
        return statements;
    }
}
