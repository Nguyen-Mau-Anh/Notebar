using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for the generic note/task link graph.</summary>
public interface ILinkRepository
{
    /// <summary>Inserts the link, or does nothing if the same edge (same source,
    /// destination, and kind) already exists — chips are inserted by typing, and
    /// typing the same reference twice is normal, not an error the user should
    /// ever see.</summary>
    Link Create(Link link);

    /// <summary>Inserts the link and saves the note's body in one transaction, so
    /// a chip's markup and the row behind it are always committed together.
    /// Throws if <paramref name="noteId"/> does not exist, rolling back the
    /// link insert too.</summary>
    Link CreateSavingNoteBody(Link link, string noteId, string bodyHtml, string bodyPlain);

    /// <summary>Deletes a link. A no-op if id does not exist.</summary>
    void Delete(string id);

    /// <summary>Every link whose source is <paramref name="from"/>.</summary>
    IReadOnlyList<Link> Outgoing(LinkTarget from);

    /// <summary>Every link whose destination is <paramref name="to"/> — the
    /// backlinks list, a reverse query on idx_link_dst.</summary>
    IReadOnlyList<Link> Incoming(LinkTarget to);

    /// <summary>Every note and task id that still exists, as one set. Called
    /// once per note load rather than once per chip, so the tombstone check
    /// (<see cref="LinkTombstone"/>) is a set lookup.</summary>
    IReadOnlySet<LinkTarget> ExistingTargets();
}
