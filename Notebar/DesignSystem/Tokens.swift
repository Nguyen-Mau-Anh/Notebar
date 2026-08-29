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

        /// The control row's height (spec §6.1); its width matches
        /// `railWidth` so it reads as capping the rail rather than floating
        /// beside it.
        static let pinHeight: CGFloat = 32
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
