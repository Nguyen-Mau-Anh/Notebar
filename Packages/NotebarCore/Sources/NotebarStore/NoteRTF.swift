import AppKit
import Foundation

/// Bridges `NSAttributedString` and the two columns a note's body is actually
/// persisted as (spec §5's `body_rtf` blob plus its `body_plain` shadow).
///
/// Lives in `NotebarStore`, not `NotebarCore`, because RTF/RTFD encoding and
/// decoding need AppKit — the APIs below are AppKit, not part of the
/// cross-platform Foundation subset `NotebarCore` is restricted to (spec
/// section 3, rule 1; `scripts/check-core-purity.sh` enforces the import ban
/// mechanically). It lives here rather than directly in the app target so
/// the migrations that touch a note's body (`Migrations.swift`) and the
/// app's `NoteEditorView` share exactly one encoder for each format — two
/// independent writers would risk producing byte-for-byte different output
/// for the same content, which is a needless place for them to disagree.
///
/// **Two formats live here on purpose.** `data(from:)`/`attributedString(from:)`
/// are plain RTF — kept exactly as they always were, because the
/// already-applied `NoteBodyRTFSchema` migration calls them by name to
/// backfill a note's old plain-text `body` into its new `body_rtf` column,
/// and that migration is not touched by this change (spec §6.2c: "the four
/// already-applied migrations are not touched" — GRDB's `DatabaseMigrator`
/// never re-runs a migration a database already has, but a *fresh* install
/// still runs it from scratch, so silently repointing what it produces would
/// be exactly the kind of change that instruction rules out). Everything
/// from here forward — the app's live editor and the new `NoteBodyRTFDSchema`
/// migration's output — uses the `rtfdData(from:)`/`attributedString(fromRTFD:)`
/// pair instead: flat RTFD, the attributed-string format that can actually
/// carry an `NSTextAttachment`. Plain RTF silently drops one on save, no
/// error, just a note that loses its picture.
public enum NoteRTF {
    /// What every empty note's editor starts from, and what a corrupt or
    /// unreadable blob falls back to rather than crashing.
    public static var empty: NSAttributedString { NSAttributedString(string: "") }

    /// Encodes an attributed string as plain RTF `Data`. Legacy: the shape
    /// `body_rtf` held from `NoteBodyRTFSchema` through the row before
    /// `NoteBodyRTFDSchema` converts it. Kept unchanged — see the type doc
    /// comment — for `NoteBodyRTFSchema`'s backfill and for
    /// `NoteBodyRTFDSchema` to read what that backfill produced. Failure
    /// here means AppKit itself rejected the conversion, which in practice
    /// means the attributed string is empty or otherwise degenerate —
    /// falling back to an empty blob is preferable to losing a save over it.
    public static func data(from attributedString: NSAttributedString) -> Data {
        (try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    /// Decodes a plain-RTF blob back into an attributed string. See
    /// `data(from:)` — legacy, kept only for the pre-`NoteBodyRTFDSchema`
    /// shape of `body_rtf`. Any blob that fails to parse falls back to
    /// `empty` rather than losing the whole note to a crash.
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

    /// Encodes an attributed string as flat RTFD `Data` — the shape
    /// `body_rtf` holds from `NoteBodyRTFDSchema` onward (spec §6.2c), and
    /// what every save goes through from here forward. "Flat" (a single
    /// `Data` blob, not a `FileWrapper` directory on disk) is what fits the
    /// existing `body_rtf BLOB` column unchanged. `rtfd(from:documentAttributes:)`
    /// returns `nil` only when AppKit itself rejects the conversion, which
    /// in practice means the attributed string is empty or otherwise
    /// degenerate — falling back to an empty blob is preferable to losing a
    /// save over it.
    /// Strips `.foregroundColor` before encoding — see the doc comment on
    /// `attributedString(fromRTFD:)` for why this is safe. Both directions
    /// strip it: on write, so a save produces appearance-neutral bytes going
    /// forward (smaller, and portable to whatever appearance the note is
    /// next opened under); on read, so every note already saved with a
    /// baked-in colour is fixed the moment it's opened, without waiting for
    /// a re-save.
    public static func rtfdData(from attributedString: NSAttributedString) -> Data {
        let colorless = strippingForegroundColor(attributedString)
        return colorless.rtfd(
            from: NSRange(location: 0, length: colorless.length),
            documentAttributes: [:]
        ) ?? Data()
    }

    /// Decodes a flat RTFD blob back into an attributed string — the read
    /// half of `rtfdData(from:)`. A brand-new note's `bodyRTF` is empty
    /// `Data` (never valid RTFD), and any blob that fails to parse — a
    /// future format, a corrupt row — falls back to `empty` rather than
    /// losing the whole note to a crash.
    ///
    /// Strips `.foregroundColor` before returning. Every note ever saved was
    /// serialized while `NoteEditorView`'s `NSTextView` had no explicit
    /// `textColor` at all, so AppKit baked in plain black regardless of the
    /// current appearance — that's what made existing notes unreadable in
    /// dark mode. This is safe to discard unconditionally *specifically*
    /// because the formatting bar (spec §6.2b: bold, italic, inline code,
    /// H1, H2, bulleted/numbered/checklist) has no colour control, so no
    /// stored `.foregroundColor` was ever a choice the user made — every one
    /// is a serialization artifact, and dropping it lets the text view's own
    /// dynamic `textColor` govern instead. This stops being true the moment
    /// a colour picker is added to the formatting bar.
    public static func attributedString(fromRTFD data: Data) -> NSAttributedString {
        guard !data.isEmpty,
              let attributedString = NSAttributedString(rtfd: data, documentAttributes: nil)
        else { return empty }
        return strippingForegroundColor(attributedString)
    }

    /// Shared by both directions of the RTFD codec — see
    /// `attributedString(fromRTFD:)` for why removing this attribute
    /// unconditionally is safe today.
    private static func strippingForegroundColor(_ attributedString: NSAttributedString) -> NSAttributedString {
        guard attributedString.length > 0 else { return attributedString }
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        mutable.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: mutable.length))
        return mutable
    }

    /// The visible-text projection stored in `body_plain` — what `note_fts`
    /// actually indexes (spec §5). `NSAttributedString.string` already
    /// strips every attribute and attachment and leaves only the characters,
    /// which is exactly the shadow column's contract: an attachment
    /// contributes no text, so embedding an image never touches FTS (spec
    /// §6.2c).
    public static func plainText(from attributedString: NSAttributedString) -> String {
        attributedString.string
    }

    /// Convenience for callers that only have a stored plain-RTF blob, not a
    /// live attributed string — `NoteBodyRTFSchema`'s own backfill path and
    /// tests describing that legacy shape.
    public static func plainText(fromRTF data: Data) -> String {
        plainText(from: attributedString(from: data))
    }

    /// Convenience for callers that only have a stored RTFD blob, not a live
    /// attributed string — the post-`NoteBodyRTFDSchema` shape.
    public static func plainText(fromRTFD data: Data) -> String {
        plainText(from: attributedString(fromRTFD: data))
    }
}
