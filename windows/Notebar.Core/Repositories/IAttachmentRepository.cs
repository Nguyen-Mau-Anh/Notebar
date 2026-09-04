using Notebar.Core.Models;

namespace Notebar.Core.Repositories;

/// <summary>Storage for images pasted or dropped into notes.</summary>
public interface IAttachmentRepository
{
    /// <summary>Creates and persists an attachment immediately.</summary>
    Attachment Create(string mimeType, byte[] data, int width, int height);

    /// <summary>A single attachment by id, or null if it does not exist.</summary>
    Attachment? Fetch(string id);

    /// <summary>Deletes every attachment whose id is not in
    /// <paramref name="referencedIds"/>. Called after a note body save, so an
    /// image the user deleted from a note stops occupying the database.</summary>
    void DeleteUnreferenced(IReadOnlySet<string> referencedIds);
}
