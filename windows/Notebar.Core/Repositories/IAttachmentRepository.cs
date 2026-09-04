using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for images pasted or dropped into notes.</summary>
public interface IAttachmentRepository
{
    /// <summary>Creates and persists an attachment immediately.</summary>
    Attachment Create(string mimeType, byte[] data, int width, int height);

    /// <summary>A single attachment by id, or null if it does not exist.</summary>
    Attachment? Fetch(string id);

    /// <summary>Deletes every attachment no note's body still references.</summary>
    /// <remarks>
    /// Takes no argument deliberately. The previous signature accepted the set of
    /// referenced ids, which asked a caller that knows about one note to assert a
    /// fact about every note — and the editor, which is the only caller, passed the
    /// asset ids of the note it had just saved. That deleted every image in every
    /// other note the first time the panel collapsed on a different one. Liveness
    /// is a property of the whole note table, so the query that decides it belongs
    /// here, where the whole table is in scope.
    /// </remarks>
    void DeleteOrphans();
}
