import AppKit
import NotebarCore

/// Polls the cursor and turns position changes into `PanelEvent`s.
///
/// Uses `NSEvent.mouseLocation`, a static property that needs **no
/// Accessibility or Input Monitoring permission**. The obvious alternative,
/// `NSEvent.addGlobalMonitorForEvents`, would drag a permission prompt in with
/// it and is deliberately not used (spec section 4.2).
///
/// This type holds no state-machine logic. It reports what the cursor did;
/// `PanelMachine` decides what that means.
@MainActor
final class CursorMonitor {

    /// Emits cursor events. Set by `PanelController`.
    var onEvent: ((PanelEvent) -> Void)?

    /// Supplies the panel's current frame, or nil when it is not on screen.
    var panelFrame: (() -> CGRect?)?

    /// Supplies the vertical band of the screen edge that arms the panel.
    /// Must match where the panel will appear — see spec section 4.2. Falls
    /// back to the whole screen if unset.
    var triggerBand: ((NSScreen) -> CGRect?)?

    /// Supplies how far the cursor may clear the panel bounds before the
    /// exit timer starts (spec §4.3's `exitSlop`, spec §6.5's "Edge
    /// tolerance" setting). Called fresh on every tick in `emitPanelEvents`
    /// rather than read once, so a change made in Settings is live on the
    /// very next tick — no restart needed. Falls back to
    /// `PanelTiming.exitSlop` if unset, keeping production behaviour
    /// unchanged for any caller (tests included) that never sets this.
    var exitSlop: () -> CGFloat = { PanelTiming.exitSlop }

    /// The cursor's current position. Injectable so the transition logic can be
    /// exercised with scripted positions; defaults to the real cursor, so
    /// production behaviour is unchanged.
    var cursorProvider: () -> CGPoint = { NSEvent.mouseLocation }

    private var timer: Timer?
    private var rate: PollRate = .idle

    private let zone = EdgeZone(
        triggerWidth: PanelTiming.triggerWidth,
        proximityWidth: PanelTiming.proximityWidth
    )

    // Previous readings, so only *transitions* are emitted rather than one
    // event per tick.
    private var lastProximity: EdgeProximity = .away
    private var wasInsidePanel = false

    private static let idleInterval: TimeInterval = 1.0 / 10.0
    private static let activeInterval: TimeInterval = 1.0 / 60.0

    func start() {
        setRate(.idle)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setRate(_ newRate: PollRate) {
        guard newRate != rate || timer == nil else { return }
        rate = newRate
        timer?.invalidate()

        let interval = newRate == .idle ? Self.idleInterval : Self.activeInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common mode keeps the timer firing while menus and drags are
        // tracking the run loop — exactly when the panel must stay responsive.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let cursor = cursorProvider()

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                ?? NSScreen.main else { return }

        emitPanelEvents(cursor: cursor)
        emitEdgeEvents(cursor: cursor, screen: triggerBand?(screen) ?? screen.frame)
    }

    private func emitEdgeEvents(cursor: CGPoint, screen: CGRect) {
        let proximity = zone.classify(cursor: cursor, screen: screen)
        defer { lastProximity = proximity }
        guard proximity != lastProximity else { return }

        switch (lastProximity, proximity) {
        case (_, .inside):
            onEvent?(.cursorEnteredTrigger)
        case (.inside, _):
            onEvent?(.cursorLeftTrigger)
        default:
            break
        }

        // Speed up while approaching so the dwell timing is accurate.
        setRate(proximity == .away ? .idle : .active)
    }

    private func emitPanelEvents(cursor: CGPoint) {
        guard let frame = panelFrame?() else {
            wasInsidePanel = false
            return
        }

        let isInside = !EdgeZone.isOutside(
            cursor: cursor,
            panelFrame: frame,
            slop: exitSlop()
        )
        defer { wasInsidePanel = isInside }
        guard isInside != wasInsidePanel else { return }

        onEvent?(isInside ? .cursorEnteredPanel : .cursorLeftPanel)
    }
}
