import SwiftUI
import NotebarCore

enum Tokens {
    enum Size {
        static let railWidth: CGFloat = 56
        static let railWidthCompact: CGFloat = 44
        /// Below this panel width the rail drops its labels.
        static let compactBreakpoint: CGFloat = 340
        /// Above this the Tasks board becomes side-by-side (M2).
        static let boardBreakpoint: CGFloat = 700

        /// The collapsed handle's footprint at the right screen edge.
        /// Defined in `PanelTiming` rather than here: `EdgeZone.triggerWidth`
        /// must equal the handle's width, so there can only be one source.
        static let handleWidth: CGFloat = PanelTiming.handleWidth
        static let handleHeight: CGFloat = PanelTiming.handleHeight

        /// The height shared by the rail's two 56pt-wide control rows (spec
        /// §6.1): the top pin/maximize row and the bottom-anchored collapse
        /// button. Width matches `railWidth` in both so each reads as
        /// capping the rail rather than floating beside it.
        static let controlRowHeight: CGFloat = 32
        /// Each of the row's two toggles (pin, maximize) — 24x24pt side by
        /// side with `Space.xs` between them.
        static let controlToggleSize: CGFloat = 24

        /// The tab toolbar row shared by every content tab (spec §6.4a).
        static let toolbarHeight: CGFloat = 36
        /// The toolbar's primary-action (`+`) hit target.
        static let actionHitTarget: CGFloat = 28

        /// Note tab strip: min/max width per tab before tail truncation.
        static let noteTabMinWidth: CGFloat = 96
        static let noteTabMaxWidth: CGFloat = 160

        /// The All-notes menu popover (spec §6.2a). `allNotesPopoverMaxHeight`
        /// caps its height and lets it scroll instead — a user with 200
        /// notes must not get a popover taller than the screen.
        static let allNotesPopoverWidth: CGFloat = 260
        static let allNotesPopoverMaxHeight: CGFloat = 360
        /// The dot marking a row whose note is already open as a tab.
        static let allNotesOpenDotSize: CGFloat = 6

        /// Caps an expanded task card's detail editor (spec §6.3a) and lets
        /// it scroll internally instead. Without a cap, a long detail would
        /// push every group below it far down the list and the board would
        /// stop being a board.
        static let taskDetailMaxHeight: CGFloat = 200

        /// The minimum height reserved for a task group with no cards —
        /// roughly one card's worth of space. Without it, an empty group
        /// shrinks to just its header row and there is nowhere to aim a
        /// drop (spec §6.3a).
        static let taskEmptyGroupMinHeight: CGFloat = 44

        /// The note editor's formatting bar (spec §6.2b): a 32pt row of
        /// 28x28pt hit targets directly beneath the tab toolbar.
        static let formattingBarHeight: CGFloat = 32
        static let formattingBarButtonSize: CGFloat = 28

        /// The `@` autocomplete popover (spec §6.4 deliverable 3), sized the
        /// same way `allNotesPopoverWidth`/`allNotesPopoverMaxHeight` are —
        /// a fixed width and a capped, scrollable height so a large note+task
        /// count never produces a popover taller than the editor itself.
        static let mentionPopoverWidth: CGFloat = 260
        static let mentionPopoverMaxHeight: CGFloat = 220
    }

    /// The note editor's type scale (spec §6.2/§6.2b): a fixed set of four
    /// sizes, each with its own line height, so body text, headings, and
    /// inline code are visually distinct without the user picking a font.
    /// `NoteTextStyling` (app target) also uses the point sizes here to tell
    /// which style a run of text currently is — see its `isHeadingFont`.
    enum Typography {
        static let bodySize: CGFloat = 14
        static let bodyLineHeight: CGFloat = 20

        static let heading1Size: CGFloat = 22
        static let heading1LineHeight: CGFloat = 28

        static let heading2Size: CGFloat = 17
        static let heading2LineHeight: CGFloat = 22

        static let codeSize: CGFloat = 13
        static let codeLineHeight: CGFloat = 18

        /// A list item's marker sits `listMarkerIndent` in from the margin;
        /// its wrapped text (and every item after the first line) sits
        /// `listIndent` in, so a marker reads as hanging left of its text.
        static let listMarkerIndent: CGFloat = 4
        static let listIndent: CGFloat = 20
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        /// The panel's own outer edge (spec §2), distinct from `md` which the
        /// collapsed handle carries.
        static let panel: CGFloat = 12
    }
}
