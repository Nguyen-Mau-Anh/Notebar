import Observation

/// State shared between `PanelController` (owns the window's geometry and
/// drives it through AppKit) and `RootView` (owns what is drawn inside it).
///
/// `PanelController` flips `isExpanded` in lockstep with the frame it
/// animates the window toward — the full panel or the collapsed handle — and
/// `RootView` reads it to pick which of the two to render. `selection` lives
/// here rather than as `RootView`'s own `@State` because the collapsed
/// handle must show the icon of the *currently selected* tab, and
/// `PanelController` has no other way to know what that is.
@Observable
final class PanelViewModel {
    var isExpanded = false
    var selection: AppTab = .notes
}
