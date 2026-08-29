import AppKit
import Observation
import QuartzCore
import NotebarCore

/// The only place where `PanelEffect` becomes an AppKit call.
///
/// Everything about *when* the panel should move lives in `PanelMachine`,
/// which is pure and unit-tested. This type is deliberately mechanical: it
/// snapshots context, feeds events to the reducer, and executes what comes
/// back (spec section 3, rule 2).
@MainActor
final class PanelController {

    private let panel: EdgePanel
    private let monitor = CursorMonitor()
    private let model: PanelViewModel

    private var state: PanelState = .hidden
    private var context = PanelContext()
    private var timers: [PanelTimer: Timer] = [:]
    private var escapeMonitor: Any?

    /// Incremented on every animation start. A completion handler that does not
    /// match the current value belongs to an animation that has been superseded,
    /// and must not run: acting on it fires `.animationFinished` for a transition
    /// that no longer exists, and can call `orderOut` on a panel that has since
    /// been reopened.
    private var animationGeneration = 0

    var isPinned: Bool {
        get { context.isPinned }
        set { context.isPinned = newValue }
    }

    init(content: NSView, model: PanelViewModel) {
        // The size here is provisional — `presentHandle()` overwrites it with
        // the collapsed handle's frame before the panel is ever displayed.
        let initial = NSRect(x: 0, y: 0, width: PanelTiming.handleWidth, height: PanelTiming.handleHeight)
        panel = EdgePanel(contentRect: initial)
        panel.contentView = content
        self.model = model
    }

    func start() {
        monitor.onEvent = { [weak self] event in self?.send(event) }
        monitor.panelFrame = { [weak self] in
            guard let self, self.panel.isVisible else { return nil }
            return self.panel.frame
        }
        monitor.triggerBand = { [weak self] screen in
            self?.triggerBand(on: screen)
        }
        presentHandle()
        monitor.start()
        observeKeyWindow()
        installEscapeMonitor()
        observePin()
    }

    /// Puts the window on screen at its collapsed handle frame the moment the
    /// app launches. Without this, the window doesn't exist until the user's
    /// first successful hover — defeating the point of a handle the user can
    /// see without knowing to hover in the first place.
    private func presentHandle() {
        guard let screen = activeScreen() else { return }
        model.isExpanded = false
        panel.setFrame(collapsedFrame(on: screen), display: false)
        panel.orderFrontRegardless()
    }

    func toggle() {
        send(.toggleRequested)
    }

    // MARK: - Reducer loop

    private func send(_ event: PanelEvent) {
        let (next, effects) = PanelMachine.reduce(state, event, context)
        state = next
        for effect in effects { apply(effect) }
    }

    private func apply(_ effect: PanelEffect) {
        switch effect {
        case .startTimer(let which):
            startTimer(which)
        case .cancelTimer(let which):
            timers[which]?.invalidate()
            timers[which] = nil
        case .showPanel:
            showPanel()
        case .hidePanel:
            hidePanel()
        case .setPollRate(let rate):
            monitor.setRate(rate)
        }
    }

    private func startTimer(_ which: PanelTimer) {
        timers[which]?.invalidate()

        let interval = which == .edgeDwell ? PanelTiming.edgeDwell : PanelTiming.exitDwell
        let event: PanelEvent = which == .edgeDwell ? .edgeDwellElapsed : .exitDwellElapsed

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timers[which] = nil
                self.send(event)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[which] = timer
    }

    // MARK: - Window movement

    private func activeScreen() -> NSScreen? {
        let cursor = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
    }

    /// Onscreen and offscreen frames for the panel on a given screen.
    /// `visibleFrame` rather than `frame` so the panel does not sit under the
    /// menu bar or over the Dock.
    ///
    /// The panel is flush to the right edge (x pinned to `area.maxX`) but
    /// vertically centred at 70% height, so it reads as a card rather than a
    /// permanent sidebar.
    private func frames(on screen: NSScreen) -> (onscreen: NSRect, offscreen: NSRect) {
        let area = screen.visibleFrame
        let height = (area.height * PanelTiming.panelHeightFraction).rounded()
        let onscreen = NSRect(
            x: area.maxX - PanelTiming.panelWidth,
            y: (area.minY + (area.height - height) / 2).rounded(),
            width: PanelTiming.panelWidth,
            height: height
        )
        return (onscreen, onscreen.offsetBy(dx: PanelTiming.panelWidth, dy: 0))
    }

    /// The vertical band of the screen edge that arms the panel.
    ///
    /// It must match where the panel will actually appear. If the whole edge
    /// armed it, touching near the top of the screen would open a panel centred
    /// far below the cursor, `CursorMonitor` would immediately report
    /// `.cursorLeftPanel`, and the panel would collapse 350 ms after opening —
    /// a flicker bug produced by a state machine behaving exactly as specified.
    private func triggerBand(on screen: NSScreen) -> NSRect {
        frames(on: screen).onscreen
    }

    /// Where the panel rests when collapsed: a small handle flush to the
    /// right edge, vertically centred, rather than fully offscreen. The
    /// window is never ordered out (see `hidePanel`), so this is also the
    /// window's resting frame between launch and the first expand.
    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let width = Tokens.Size.handleWidth
        let height = Tokens.Size.handleHeight
        return NSRect(
            x: area.maxX - width,
            y: (area.minY + (area.height - height) / 2).rounded(),
            width: width,
            height: height
        )
    }

    private func showPanel() {
        guard let screen = activeScreen() else { return }
        let (onscreen, offscreen) = frames(on: screen)

        if !panel.isVisible {
            panel.setFrame(offscreen, display: false)
            // orderFrontRegardless shows the panel WITHOUT activating the app,
            // so the frontmost application keeps focus until the user clicks in.
            panel.orderFrontRegardless()
        }

        model.isExpanded = true
        animate(to: onscreen, duration: PanelTiming.expandDuration)
    }

    private func hidePanel() {
        guard panel.isVisible else {
            // `.hidePanel` should only ever be emitted while the panel is
            // expanded or expanding. If this fires, the reducer and the
            // window have drifted out of sync. Surface it instead of silently
            // doing nothing — but a diagnostic must not be more destructive
            // than the bug it reports, so this logs rather than asserts: it
            // is reachable in production (e.g. `showPanel()` bailing out when
            // `activeScreen()` returns nil), and `assertionFailure` would trap
            // a Debug build over a benign no-op. Becomes a proper test
            // assertion once there is a test target for the app (M1).
            NSLog("Notebar: hidePanel effect received while the panel is not visible — reducer and window are out of sync")
            return
        }
        guard let screen = activeScreen() else { return }

        // The panel retreats to a visible handle rather than being ordered
        // out. Previously a stale animation completion could order the
        // window out after it had already been reopened, leaving the reducer
        // in `.expanded` while `panel.isVisible == false`. With the window
        // always visible, the worst a stale completion can do is set a frame
        // the next event corrects.
        //
        // `isExpanded` flips on completion, not here at the start: `RootView`
        // switches to the 30x56 handle content the instant it flips, so
        // flipping early would render the handle inside the still-full-size
        // window for the whole 140ms shrink. `animate`'s `animationGeneration`
        // guard already keeps a superseded collapse's completion from firing.
        animate(to: collapsedFrame(on: screen), duration: PanelTiming.collapseDuration) { [weak self] in
            self?.model.isExpanded = false
        }
    }

    private func animate(
        to frame: NSRect,
        duration: TimeInterval,
        then completion: (() -> Void)? = nil
    ) {
        animationGeneration &+= 1
        let generation = animationGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            guard let self, generation == self.animationGeneration else { return }
            completion?()
            // The reducer decides what "finished" means for the current state.
            self.send(.animationFinished)
        })
    }

    /// `model.isPinned` is the only channel from SwiftUI into `isPinned` —
    /// the rail's pin button sets it, and this mirrors it into `context`
    /// every time it changes. `withObservationTracking` must be re-armed
    /// after every fire; it only observes the next single change otherwise.
    private func observePin() {
        withObservationTracking {
            _ = model.isPinned
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPinned = self.model.isPinned
                self.observePin()
            }
        }
    }

    // MARK: - Context signals

    /// In M0 only `isWindowKey` has a real source; there are no editors or
    /// drags yet. M1 and M2 wire `isEditorFocused`, `msSinceLastKeystroke`,
    /// `isDragging`, and `hasOpenOverlay` from the SwiftUI layer.
    private func observeKeyWindow() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.context.isWindowKey = true }
        }
        center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.context.isWindowKey = false }
        }
    }

    /// A *local* monitor, which needs no permission — it only sees events
    /// already routed to this app.
    private func installEscapeMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Escape
            MainActor.assumeIsolated { self?.send(.escapePressed) }
            return nil
        }
    }
}
