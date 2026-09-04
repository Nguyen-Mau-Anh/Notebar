namespace Notebar.Core.Models;

/// <summary>An image pasted or dropped into a note, stored as a row rather than
/// embedded in the body.</summary>
/// <remarks>
/// The macOS build embedded images in the note body blob and then needed a
/// separate summaries query to avoid reading every screenshot back just to draw
/// a list of note names. Storing them separately from the start costs nothing
/// extra and removes that whole class of problem: a note body is always small.
/// Width and Height are the intrinsic pixel dimensions after downscaling, so the
/// editor can lay the image out before the bytes have loaded.
/// </remarks>
public sealed record Attachment(
    string Id, string MimeType, byte[] Data, int Width, int Height, DateTimeOffset CreatedAt);
