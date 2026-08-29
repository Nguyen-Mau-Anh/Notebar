import AppKit
import Foundation

/// Bridges `NSAttributedString` and the two columns a note's body is actually
/// persisted as (spec §5's `body_rtf` blob plus its `body_plain` shadow).
///
/// Lives in `NotebarStore`, not `NotebarCore`, because RTF encoding/decoding
/// needs AppKit — `NSAttributedString(data:options:documentAttributes:)` and
/// its RTF-writing counterpart are AppKit APIs, not part of the cross-platform
/// Foundation subset `NotebarCore` is restricted to (spec section 3, rule 1;
/// `scripts/check-core-purity.sh` enforces the import ban mechanically). It
/// lives here rather than directly in the app target so the migration that
/// backfills existing plain-text bodies into RTF (`Migrations.swift`) and the
/// app's `NoteEditorView` share exactly one encoder — two independent RTF
/// writers would risk producing byte-for-byte different output for the same
/// content, which is a needless place for the two to disagree.
public enum NoteRTF {
    /// What every empty note's editor starts from, and what a corrupt or
    /// unreadable blob falls back to rather than crashing.
    public static var empty: NSAttributedString { NSAttributedString(string: "") }

    /// Encodes an attributed string as RTF `Data`, the shape `body_rtf` is
    /// stored as. Failure here means AppKit itself rejected the conversion,
    /// which in practice means the attributed string is empty or otherwise
    /// degenerate — falling back to an empty blob is preferable to losing a
    /// save over it.
    public static func data(from attributedString: NSAttributedString) -> Data {
        (try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    /// Decodes an RTF blob back into an attributed string. A brand-new note's
    /// `bodyRTF` is empty `Data` (never valid RTF), and any blob that fails to
    /// parse — a future format, a corrupt row — falls back to `empty` rather
    /// than losing the whole note to a crash.
    public static func attributedString(from data: Data) -> NSAttributedString {
        guard !data.isEmpty,
              let attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              )
        else { return empty }
        return attributedString
    }

    /// The visible-text projection stored in `body_plain` — what `note_fts`
    /// actually indexes (spec §5). `NSAttributedString.string` already
    /// strips every attribute and leaves only the characters, which is
    /// exactly the shadow column's contract.
    public static func plainText(from attributedString: NSAttributedString) -> String {
        attributedString.string
    }

    /// Convenience for callers that only have the stored blob, not a live
    /// attributed string — the migration backfill path.
    public static func plainText(fromRTF data: Data) -> String {
        plainText(from: attributedString(from: data))
    }
}
