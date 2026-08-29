import Foundation

/// The `notebar://note/<id>` / `notebar://task/<id>` custom-URL scheme spec
/// §6.4 puts on every chip's `.link` attribute. Lives here, not in the app
/// target, so both chip insertion (`NoteEditorView`, building the URL) and
/// click handling (`textView(_:clickedOnLink:at:)`, parsing it back) share
/// exactly one encoder/decoder — the same reasoning `NoteRTF`'s doc comment
/// gives for why a shared codec beats two independent ones that could drift.
/// No AppKit needed for URL string handling, so this stays in `NotebarCore`
/// rather than `NotebarStore`, and is unit-testable without a database.
public enum LinkURL {
    public static let scheme = "notebar"

    /// Builds the chip URL for a given target. Force-unwrapped: `type.rawValue`
    /// is always `"note"` or `"task"` and `id` is always a UUID string (every
    /// call site passes `Note.ID`/`TaskItem.ID`), neither of which can
    /// produce a URL `URLComponents` rejects.
    public static func url(for type: LinkEntityType, id: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = type.rawValue
        components.path = "/" + id
        return components.url!
    }

    public static func url(for target: LinkTarget) -> URL {
        url(for: target.type, id: target.id)
    }

    /// The inverse of `url(for:id:)`. `nil` for anything not built by this
    /// type — a link to a scheme this app doesn't own, or a malformed/future
    /// `notebar://` URL neither case above ever produces — so a click on a
    /// chip whose target this can't parse does nothing rather than crash
    /// (spec §6.4 deliverable 4).
    public static func parse(_ url: URL) -> LinkTarget? {
        guard url.scheme == scheme, let host = url.host, let type = LinkEntityType(rawValue: host) else {
            return nil
        }
        let id = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard !id.isEmpty else { return nil }
        return LinkTarget(type: type, id: id)
    }
}
