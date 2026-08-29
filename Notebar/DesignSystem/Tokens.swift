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
