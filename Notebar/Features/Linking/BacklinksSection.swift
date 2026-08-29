import SwiftUI
import NotebarCore

/// The inbound-references list every note and task shows (spec §6.4
/// deliverable 1): one query on `idx_link_dst` via
/// `PanelViewModel.backlinks(for:)`, reused unchanged by both the note
/// editor (`NotesTab`'s `NoteEditorContainer`) and an expanded task card
/// (`TasksTab`'s `TaskCardView`) — the caller only ever differs in which
/// `LinkTarget` it asks about. Row look mirrors `MentionPopoverView`'s
/// exactly, since both list the same `MentionCandidate` shape: a note or a
/// task, projected down to an id, a type, and a title.
///
/// **Hidden entirely when there are no backlinks.** An empty "Backlinks"
/// header on every note and task would be pure noise — this reads
/// `model.backlinks(for:)` right here and produces nothing at all
/// (`EmptyView`, via the `if`) rather than a header over an empty list.
struct BacklinksSection: View {
    let model: PanelViewModel
    let target: LinkTarget

    var body: some View {
        let backlinks = model.backlinks(for: target)
        if !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Divider()

                Text("Backlinks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Tokens.Space.md)
                    .padding(.top, Tokens.Space.sm)
                    .padding(.bottom, Tokens.Space.xs)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(backlinks) { candidate in
                            BacklinkRow(candidate: candidate) {
                                // Spec §6.4 deliverable 4's "same path a chip
                                // click uses" — this is that path,
                                // `PanelViewModel.openLinkTarget`, not a
                                // second way of opening a note/task.
                                model.openLinkTarget(LinkTarget(type: candidate.type, id: candidate.id))
                            }
                        }
                    }
                }
                .frame(maxHeight: Tokens.Size.backlinksMaxHeight)
            }
        }
    }
}

private struct BacklinkRow: View {
    let candidate: MentionCandidate
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Tokens.Space.sm) {
                Image(systemName: candidate.type == .note ? "doc.text" : "checklist")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(candidate.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Space.md)
            .padding(.vertical, Tokens.Space.xs)
            .background(isHovering ? Color.accentColor.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Referenced by \(candidate.title)")
    }
}
