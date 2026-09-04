using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for the open-tab strip. Open tabs survive a restart; this is
/// what makes that possible.</summary>
public interface IOpenTabRepository
{
    /// <summary>Every open tab, ordered by SortOrder ascending.</summary>
    IReadOnlyList<OpenTab> All();

    /// <summary>Replaces the entire strip with <paramref name="tabs"/> in one
    /// transaction. The strip is a handful of rows that change only on open,
    /// close, reorder, and select — never per keystroke — so a full replace is
    /// simpler than diffing and cheap enough not to matter.</summary>
    void ReplaceAll(IReadOnlyList<OpenTab> tabs);
}
