# Notebar M0 (Shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running menu-bar-only macOS app whose panel slides out when the cursor reaches the right screen edge, shows a three-tab rail with empty tabs, and collapses when the cursor leaves — without ever collapsing while the user is mid-thought.

**Architecture:** The panel's behaviour is a pure reducer in a UI-free Swift package, so every flicker scenario is a unit test rather than something reproduced by waving a mouse at the screen. AppKit is quarantined to three thin files that translate reducer effects into real window calls. Everything visible is SwiftUI.

**Tech Stack:** Swift 6.3 (Swift 5 language mode) · SwiftUI + AppKit · XcodeGen · Swift Testing · macOS 26+

**Spec:** `docs/superpowers/specs/2026-08-29-notebar-design.md`

## Global Constraints

- **Deployment target:** macOS 26.0 for the app target. `NotebarCore` targets macOS 14 — it has no UI dependency and a lower floor keeps it portable.
- **Language mode:** Swift 5 (`SWIFT_VERSION = 5.0`, `.swiftLanguageMode(.v5)`), `SWIFT_STRICT_CONCURRENCY = minimal`. Spec §2. Do not raise these in M0.
- **`NotebarCore` must never import `AppKit`, `SwiftUI`, or `UIKit`.** Spec §3 rule 1. Enforced by `scripts/check-core-purity.sh`, which runs in `make check` and must pass before every commit.
- **`PanelMachine` must be a pure function.** No timers, no clocks, no I/O, no `Date()` calls inside `reduce`. All time arrives as event payloads. Spec §3 rule 2.
- **No permission-requiring APIs.** Do not use `NSEvent.addGlobalMonitorForEvents` or `CGEvent` taps. Cursor position comes from `NSEvent.mouseLocation`; the hotkey uses Carbon `RegisterEventHotKey`. Both are permission-free. Spec §4.2, §1 success criterion 5.
- **Timing defaults** (spec §4.3), all as named constants, never inline literals: `edgeDwell` 120 ms · `triggerWidth` 2 pt · `proximityWidth` 80 pt · `exitSlop` 24 pt · `exitDwell` 350 ms · `expandDuration` 180 ms · `collapseDuration` 140 ms.
- **Bundle identifier:** `com.anhnm.notebar`. **`LSUIElement` = true** — no Dock icon.
- **Commit after every task.** Workspace rule: commit and push at every checkpoint.

## File Structure

| File | Responsibility |
|---|---|
| `project.yml` | XcodeGen project definition. The `.xcodeproj` is generated, never hand-edited, and is gitignored. |
| `Makefile` | `gen`, `build`, `test`, `check`, `run` — the npm-scripts equivalent. |
| `scripts/check-core-purity.sh` | Fails if `NotebarCore` imports any UI framework. |
| `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelState.swift` | State, event, effect, timer, poll-rate, and context types. Pure data. |
| `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelMachine.swift` | `reduce` and `shouldCollapse`. Pure logic. |
| `Packages/NotebarCore/Sources/NotebarCore/Panel/EdgeZone.swift` | Cursor-position → proximity classification. Pure geometry. |
| `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelTiming.swift` | The timing constants above. |
| `Packages/NotebarCore/Tests/NotebarCoreTests/*` | Swift Testing suites for the three files above. |
| `Notebar/App/NotebarApp.swift` | `@main`, `NSApplicationDelegateAdaptor`, environment wiring. |
| `Notebar/App/AppDelegate.swift` | Lifecycle, owns `PanelController` and `StatusItemController`. |
| `Notebar/App/StatusItemController.swift` | Menu bar item and its menu. |
| `Notebar/App/GlobalHotKey.swift` | Carbon hotkey registration. |
| `Notebar/Panel/EdgePanel.swift` | `NSPanel` subclass and window flags. Nothing else. |
| `Notebar/Panel/CursorMonitor.swift` | Adaptive polling timer; emits cursor events. Owns no state machine logic. |
| `Notebar/Panel/PanelController.swift` | The only file that turns `PanelEffect` into AppKit calls. |
| `Notebar/Features/RootView.swift` | Tab rail plus the selected tab's content. |
| `Notebar/Features/AppTab.swift` | The three-tab enum. |
| `Notebar/Features/{Notes,Tasks,Settings}/*Tab.swift` | Empty placeholder tabs in M0. |
| `Notebar/DesignSystem/Tokens.swift` | Colours, spacing, radii. |

---

### Task 1: Project skeleton that launches

**Files:**
- Create: `project.yml`, `Makefile`, `.gitignore` (modify), `scripts/check-core-purity.sh`
- Create: `Packages/NotebarCore/Package.swift`
- Create: `Packages/NotebarCore/Sources/NotebarCore/NotebarCore.swift`
- Create: `Packages/NotebarCore/Tests/NotebarCoreTests/SmokeTests.swift`
- Create: `Notebar/App/NotebarApp.swift`, `Notebar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable `Notebar` scheme; `make build`, `make test`, `make check`; the `NotebarCore` module importable from the app target.

- [ ] **Step 1: Install XcodeGen**

The `.xcodeproj` format is a merge-conflict generator and cannot be hand-edited safely. XcodeGen turns a readable YAML file into the project, so the project definition lives in git as text.

```bash
brew install xcodegen
xcodegen --version
```

- [ ] **Step 2: Create the NotebarCore package**

```bash
mkdir -p Packages/NotebarCore/Sources/NotebarCore/Panel
mkdir -p Packages/NotebarCore/Tests/NotebarCoreTests
```

`Packages/NotebarCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotebarCore",
    // Deliberately lower than the app's macOS 26 floor: this package has no UI
    // dependency, and keeping its floor low keeps it portable (spec section 3, rule 1).
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotebarCore", targets: ["NotebarCore"])
    ],
    targets: [
        .target(
            name: "NotebarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NotebarCoreTests",
            dependencies: ["NotebarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`Packages/NotebarCore/Sources/NotebarCore/NotebarCore.swift`:

```swift
import Foundation

/// Namespace marker for the pure-Swift core.
///
/// This module must never import AppKit, SwiftUI, or UIKit.
/// `scripts/check-core-purity.sh` enforces that mechanically.
public enum NotebarCore {
    public static let version = "0.1.0"
}
```

`Packages/NotebarCore/Tests/NotebarCoreTests/SmokeTests.swift`:

```swift
import Testing
@testable import NotebarCore

@Test("core module is importable")
func coreIsImportable() {
    #expect(NotebarCore.version == "0.1.0")
}
```

- [ ] **Step 3: Run the package tests to prove the toolchain works**

```bash
cd Packages/NotebarCore && swift test && cd ../..
```

Expected: `Test run with 1 test passed`.

If this fails with an unknown `swiftLanguageMode`, the Swift toolchain is older than 6.0 — check `swift --version`.

- [ ] **Step 4: Write the core-purity guard**

`scripts/check-core-purity.sh`:

```bash
#!/usr/bin/env bash
# NotebarCore must stay free of Apple UI frameworks so it can be ported.
# See spec section 3, rule 1.
set -euo pipefail

if grep -rnE '^[[:space:]]*import[[:space:]]+(AppKit|SwiftUI|UIKit)' \
     Packages/NotebarCore/Sources/ 2>/dev/null; then
  echo "ERROR: NotebarCore imports a UI framework (see above)." >&2
  echo "Move that code into the Notebar app target instead." >&2
  exit 1
fi

echo "core purity: OK"
```

```bash
chmod +x scripts/check-core-purity.sh
./scripts/check-core-purity.sh
```

Expected: `core purity: OK`.

- [ ] **Step 5: Write the app entry points**

`Notebar/App/NotebarApp.swift`:

```swift
import SwiftUI

@main
struct NotebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The panel is an NSPanel owned by AppDelegate, not a SwiftUI Scene,
        // because SwiftUI has no equivalent for a non-activating floating panel.
        // Settings{} gives the app a valid empty scene graph.
        Settings { EmptyView() }
    }
}
```

`Notebar/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already hides the Dock icon; this makes the
        // behaviour explicit and survives someone flipping the plist by accident.
        NSApp.setActivationPolicy(.accessory)
        NSLog("Notebar launched")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 6: Write the XcodeGen project definition**

`project.yml`:

```yaml
name: Notebar
options:
  bundleIdPrefix: com.anhnm
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
    DEAD_CODE_STRIPPING: YES

packages:
  NotebarCore:
    path: Packages/NotebarCore

targets:
  Notebar:
    type: application
    platform: macOS
    sources:
      - path: Notebar
    dependencies:
      - package: NotebarCore
        product: NotebarCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.anhnm.notebar
        PRODUCT_NAME: Notebar
        ENABLE_HARDENED_RUNTIME: YES
        COMBINE_HIDPI_IMAGES: YES
    info:
      path: Notebar/Info.plist
      properties:
        CFBundleName: Notebar
        CFBundleDisplayName: Notebar
        CFBundlePackageType: APPL
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        LSMinimumSystemVersion: "$(MACOSX_DEPLOYMENT_TARGET)"
        # Menu-bar-only app: no Dock icon, no app menu.
        LSUIElement: true
        NSHumanReadableCopyright: ""
```

- [ ] **Step 7: Write the Makefile**

`Makefile`:

```makefile
.PHONY: gen build test check run clean all

PROJECT := Notebar.xcodeproj
SCHEME  := Notebar
CONFIG  := Debug
APP     := $(HOME)/Library/Developer/Xcode/DerivedData/Notebar-*/Build/Products/$(CONFIG)/Notebar.app

all: check test build

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build -quiet

# Core tests need no Xcode and finish in about a second. Use these constantly.
test:
	cd Packages/NotebarCore && swift test

check:
	./scripts/check-core-purity.sh

run: build
	@pkill -x Notebar || true
	@open $(APP)

clean:
	rm -rf $(PROJECT) .build Packages/NotebarCore/.build
```

- [ ] **Step 8: Ignore the generated project**

Append to `.gitignore`:

```
# Generated by XcodeGen — edit project.yml instead
*.xcodeproj
xcuserdata/
.build/
DerivedData/
```

- [ ] **Step 9: Generate, build, and run**

```bash
make check && make test && make build
```

Expected: `core purity: OK`, 1 test passed, and a build that ends with no error lines. Then:

```bash
make run
```

Expected: no Dock icon appears, no window appears, and `log stream --predicate 'process == "Notebar"' --style compact` shows `Notebar launched`. The app is running invisibly — that is correct at this stage.

```bash
pkill -x Notebar
```

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "M0.1: project skeleton with XcodeGen, NotebarCore package, purity guard"
git push origin main
```

---

### Task 2: PanelMachine — states, events, and transitions

**Files:**
- Create: `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelTiming.swift`
- Create: `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelState.swift`
- Create: `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelMachine.swift`
- Test: `Packages/NotebarCore/Tests/NotebarCoreTests/PanelMachineTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum PanelState { case hidden, expanding, expanded, collapsing }`
  - `enum PanelEvent` — cases listed in Step 2 below
  - `enum PanelEffect { case startTimer(PanelTimer), cancelTimer(PanelTimer), showPanel, hidePanel, setPollRate(PollRate) }`
  - `enum PanelTimer { case edgeDwell, exitDwell }`
  - `enum PollRate { case idle, active }`
  - `struct PanelContext` — six suppression signals plus `isPinned`
  - `enum PanelMachine { static func reduce(_ state: PanelState, _ event: PanelEvent, _ context: PanelContext) -> (PanelState, [PanelEffect]) }`

Task 3 fills in `PanelMachine.shouldCollapse`. Task 6 consumes `reduce` and interprets `[PanelEffect]`.

- [ ] **Step 1: Write the timing constants**

`PanelTiming.swift`:

```swift
import Foundation

/// Timing defaults from spec section 4.3. Every value here becomes a user
/// setting in M4; nothing may inline these numbers at a call site.
public enum PanelTiming {
    /// Cursor must rest in the trigger zone this long before expanding.
    /// Prevents accidental opens when reaching for a scrollbar.
    public static let edgeDwell: TimeInterval = 0.120

    /// Cursor must stay outside the panel this long before collapsing.
    public static let exitDwell: TimeInterval = 0.350

    /// Width of the activation strip at the screen edge.
    public static let triggerWidth: CGFloat = 2

    /// Distance from the edge at which polling speeds up.
    public static let proximityWidth: CGFloat = 80

    /// Cursor must clear the panel bounds by this margin before the exit timer starts.
    public static let exitSlop: CGFloat = 24

    public static let expandDuration: TimeInterval = 0.180

    /// Deliberately faster than expanding — reads as responsive, not sluggish.
    public static let collapseDuration: TimeInterval = 0.140
}
```

- [ ] **Step 2: Write the state, event, and effect types**

`PanelState.swift`:

```swift
import Foundation

public enum PanelState: Equatable, Sendable {
    case hidden
    case expanding
    case expanded
    case collapsing
}

public enum PanelTimer: Equatable, Sendable {
    case edgeDwell
    case exitDwell
}

public enum PollRate: Equatable, Sendable {
    /// Cursor is far from the edge. 10 Hz.
    case idle
    /// Cursor is near the edge or the panel is open. 60 Hz.
    case active
}

public enum PanelEvent: Equatable, Sendable {
    /// Cursor entered the narrow activation strip at the screen edge.
    case cursorEnteredTrigger
    /// Cursor left the activation strip before the dwell elapsed.
    case cursorLeftTrigger
    /// Cursor moved inside the panel's bounds.
    case cursorEnteredPanel
    /// Cursor moved further than `exitSlop` outside the panel's bounds.
    case cursorLeftPanel
    /// The edge-dwell timer fired.
    case edgeDwellElapsed
    /// The exit-dwell timer fired.
    case exitDwellElapsed
    /// A show or hide animation finished.
    case animationFinished
    /// Global hotkey pressed, or the menu bar toggle chosen.
    case toggleRequested
    case escapePressed
}

/// Side effects the reducer requests. `PanelController` is the only code that
/// turns these into real AppKit calls — that separation is what makes every
/// transition testable without a window.
public enum PanelEffect: Equatable, Sendable {
    case startTimer(PanelTimer)
    case cancelTimer(PanelTimer)
    case showPanel
    case hidePanel
    case setPollRate(PollRate)
}

/// The suppression signals from spec section 4.4. Snapshotted by
/// `PanelController` and passed into every `reduce` call.
public struct PanelContext: Equatable, Sendable {
    /// User pinned the panel, or summoned it by hotkey.
    public var isPinned: Bool
    /// A menu, popover, or sheet is open.
    public var hasOpenOverlay: Bool
    /// A drag is in flight.
    public var isDragging: Bool
    /// A text editor holds first responder.
    public var isEditorFocused: Bool
    /// Milliseconds since the last keystroke, or nil if none this session.
    public var msSinceLastKeystroke: Int?
    /// The panel is the key window.
    public var isWindowKey: Bool

    public init(
        isPinned: Bool = false,
        hasOpenOverlay: Bool = false,
        isDragging: Bool = false,
        isEditorFocused: Bool = false,
        msSinceLastKeystroke: Int? = nil,
        isWindowKey: Bool = false
    ) {
        self.isPinned = isPinned
        self.hasOpenOverlay = hasOpenOverlay
        self.isDragging = isDragging
        self.isEditorFocused = isEditorFocused
        self.msSinceLastKeystroke = msSinceLastKeystroke
        self.isWindowKey = isWindowKey
    }

    /// A context with every suppression signal off.
    public static let idle = PanelContext()
}
```

- [ ] **Step 3: Write the failing transition tests**

`Packages/NotebarCore/Tests/NotebarCoreTests/PanelMachineTests.swift`:

```swift
import Testing
@testable import NotebarCore

@Suite("PanelMachine transitions")
struct PanelMachineTransitionTests {

    @Test("entering the trigger zone starts the dwell timer but does not expand")
    func enteringTriggerStartsDwell() {
        let (state, effects) = PanelMachine.reduce(.hidden, .cursorEnteredTrigger, .idle)
        #expect(state == .hidden)
        #expect(effects.contains(.startTimer(.edgeDwell)))
        #expect(effects.contains(.setPollRate(.active)))
    }

    @Test("leaving the trigger zone before dwell cancels the timer")
    func leavingTriggerCancelsDwell() {
        let (state, effects) = PanelMachine.reduce(.hidden, .cursorLeftTrigger, .idle)
        #expect(state == .hidden)
        #expect(effects.contains(.cancelTimer(.edgeDwell)))
        #expect(effects.contains(.setPollRate(.idle)))
    }

    @Test("dwell elapsing expands the panel")
    func dwellElapsedExpands() {
        let (state, effects) = PanelMachine.reduce(.hidden, .edgeDwellElapsed, .idle)
        #expect(state == .expanding)
        #expect(effects.contains(.showPanel))
    }

    @Test("animation finishing completes the expansion")
    func expandingCompletes() {
        let (state, _) = PanelMachine.reduce(.expanding, .animationFinished, .idle)
        #expect(state == .expanded)
    }

    @Test("leaving the panel starts the exit timer, it does not collapse immediately")
    func leavingPanelStartsExitTimer() {
        let (state, effects) = PanelMachine.reduce(.expanded, .cursorLeftPanel, .idle)
        #expect(state == .expanded)
        #expect(effects.contains(.startTimer(.exitDwell)))
        #expect(!effects.contains(.hidePanel))
    }

    @Test("returning to the panel cancels a pending collapse")
    func returningCancelsExitTimer() {
        let (state, effects) = PanelMachine.reduce(.expanded, .cursorEnteredPanel, .idle)
        #expect(state == .expanded)
        #expect(effects.contains(.cancelTimer(.exitDwell)))
    }

    @Test("exit dwell elapsing collapses the panel")
    func exitDwellCollapses() {
        let (state, effects) = PanelMachine.reduce(.expanded, .exitDwellElapsed, .idle)
        #expect(state == .collapsing)
        #expect(effects.contains(.hidePanel))
    }

    @Test("collapse animation finishing returns to hidden and slows polling")
    func collapseCompletes() {
        let (state, effects) = PanelMachine.reduce(.collapsing, .animationFinished, .idle)
        #expect(state == .hidden)
        #expect(effects.contains(.setPollRate(.idle)))
    }

    @Test("re-entering during collapse reverses it")
    func reEntryDuringCollapseReverses() {
        let (state, effects) = PanelMachine.reduce(.collapsing, .cursorEnteredPanel, .idle)
        #expect(state == .expanding)
        #expect(effects.contains(.showPanel))
    }

    @Test("escape collapses even when pinned")
    func escapeAlwaysCollapses() {
        let pinned = PanelContext(isPinned: true)
        let (state, effects) = PanelMachine.reduce(.expanded, .escapePressed, pinned)
        #expect(state == .collapsing)
        #expect(effects.contains(.hidePanel))
    }

    @Test("toggle opens when hidden and closes when expanded")
    func toggleFlips() {
        let (opened, openEffects) = PanelMachine.reduce(.hidden, .toggleRequested, .idle)
        #expect(opened == .expanding)
        #expect(openEffects.contains(.showPanel))

        let (closed, closeEffects) = PanelMachine.reduce(.expanded, .toggleRequested, .idle)
        #expect(closed == .collapsing)
        #expect(closeEffects.contains(.hidePanel))
    }

    @Test("unhandled pairs are inert")
    func unhandledPairsAreInert() {
        let (state, effects) = PanelMachine.reduce(.hidden, .exitDwellElapsed, .idle)
        #expect(state == .hidden)
        #expect(effects.isEmpty)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they fail**

```bash
cd Packages/NotebarCore && swift test 2>&1 | tail -20; cd ../..
```

Expected: compile failure, `cannot find 'PanelMachine' in scope`. That is the correct failure — the type does not exist yet.

- [ ] **Step 5: Write the reducer**

`PanelMachine.swift`:

```swift
import Foundation

/// The panel's behaviour as a pure function.
///
/// This type must never import AppKit, hold state, read a clock, or start a
/// timer. Time enters only as events (`edgeDwellElapsed`, `exitDwellElapsed`)
/// that `PanelController` schedules on the reducer's instruction. That is what
/// makes flicker scenarios — the bugs that are miserable to reproduce by
/// hand — into ordinary table tests.
public enum PanelMachine {

    public static func reduce(
        _ state: PanelState,
        _ event: PanelEvent,
        _ context: PanelContext
    ) -> (PanelState, [PanelEffect]) {

        switch (state, event) {

        // Approaching the edge: arm the dwell timer, speed up polling.
        case (.hidden, .cursorEnteredTrigger):
            return (.hidden, [.startTimer(.edgeDwell), .setPollRate(.active)])

        case (.hidden, .cursorLeftTrigger):
            return (.hidden, [.cancelTimer(.edgeDwell), .setPollRate(.idle)])

        case (.hidden, .edgeDwellElapsed):
            return (.expanding, [.showPanel])

        case (.expanding, .animationFinished):
            return (.expanded, [])

        // Leaving an open panel only *arms* the collapse. Whether it is allowed
        // to fire is decided when the timer elapses, against a fresh context.
        case (.expanded, .cursorLeftPanel):
            guard shouldCollapse(context) else { return (.expanded, []) }
            return (.expanded, [.startTimer(.exitDwell)])

        case (.expanded, .cursorEnteredPanel):
            return (.expanded, [.cancelTimer(.exitDwell)])

        case (.expanded, .exitDwellElapsed):
            guard shouldCollapse(context) else { return (.expanded, []) }
            return (.collapsing, [.hidePanel])

        case (.collapsing, .animationFinished):
            return (.hidden, [.setPollRate(.idle)])

        // Cursor came back mid-collapse: reverse without touching hidden.
        case (.collapsing, .cursorEnteredPanel), (.collapsing, .cursorEnteredTrigger):
            return (.expanding, [.showPanel])

        // Escape overrides every suppression signal, pinning included (spec 4.3).
        case (.expanded, .escapePressed), (.expanding, .escapePressed):
            return (.collapsing, [.hidePanel, .cancelTimer(.exitDwell)])

        case (.hidden, .toggleRequested), (.collapsing, .toggleRequested):
            return (.expanding, [.showPanel, .setPollRate(.active)])

        case (.expanded, .toggleRequested), (.expanding, .toggleRequested):
            return (.collapsing, [.hidePanel])

        default:
            return (state, [])
        }
    }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

```bash
cd Packages/NotebarCore && swift test 2>&1 | tail -20; cd ../..
```

Expected: still failing — `shouldCollapse` does not exist yet. Add a temporary stub at the bottom of `PanelMachine`:

```swift
    // Replaced properly in Task 3.
    static func shouldCollapse(_ context: PanelContext) -> Bool { true }
```

Re-run. Expected: `Test run with 12 tests passed`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "M0.2: PanelMachine states, events, and transitions with tests"
git push origin main
```

---

### Task 3: Collapse suppression policy

> **This task contains the one decision left deliberately to the author.** The
> transitions are settled; what remains is how eagerly the panel should get out
> of the way, which is a question about how you work rather than a technical one.

**Files:**
- Modify: `Packages/NotebarCore/Sources/NotebarCore/Panel/PanelMachine.swift`
- Test: `Packages/NotebarCore/Tests/NotebarCoreTests/CollapsePolicyTests.swift`

**Interfaces:**
- Consumes: `PanelContext`, `PanelMachine.reduce` from Task 2.
- Produces: `PanelMachine.shouldCollapse(_ context: PanelContext) -> Bool`, and `PanelTiming.typingGrace: TimeInterval`.

- [ ] **Step 1: Add the typing-grace constant**

In `PanelTiming.swift`:

```swift
    /// How long after the last keystroke the panel still counts as "in use".
    /// Referenced by `PanelMachine.shouldCollapse`.
    public static let typingGrace: TimeInterval = 2.0
```

- [ ] **Step 2: Write the invariant tests**

These encode requirements from spec section 4.4 that are not matters of taste. They must pass whatever policy is written.

`Packages/NotebarCore/Tests/NotebarCoreTests/CollapsePolicyTests.swift`:

```swift
import Testing
@testable import NotebarCore

@Suite("Collapse suppression invariants")
struct CollapsePolicyInvariantTests {

    @Test("a pinned panel never collapses on cursor exit")
    func pinnedNeverCollapses() {
        #expect(PanelMachine.shouldCollapse(PanelContext(isPinned: true)) == false)
    }

    @Test("a panel with an open menu never collapses")
    func openOverlayNeverCollapses() {
        #expect(PanelMachine.shouldCollapse(PanelContext(hasOpenOverlay: true)) == false)
    }

    @Test("a panel with a drag in flight never collapses")
    func draggingNeverCollapses() {
        #expect(PanelMachine.shouldCollapse(PanelContext(isDragging: true)) == false)
    }

    @Test("an idle panel does collapse")
    func idlePanelCollapses() {
        #expect(PanelMachine.shouldCollapse(.idle) == true)
    }

    @Test("pinning survives a full exit-dwell cycle")
    func pinnedSurvivesExitDwell() {
        let pinned = PanelContext(isPinned: true)
        let (state, effects) = PanelMachine.reduce(.expanded, .exitDwellElapsed, pinned)
        #expect(state == .expanded)
        #expect(!effects.contains(.hidePanel))
    }

    @Test("a drag released outside does not take the panel with it")
    func dragInFlightSurvivesExit() {
        let dragging = PanelContext(isDragging: true)
        let (state, _) = PanelMachine.reduce(.expanded, .cursorLeftPanel, dragging)
        #expect(state == .expanded)
    }
}
```

- [ ] **Step 3: Run and confirm the invariant tests fail**

```bash
cd Packages/NotebarCore && swift test 2>&1 | tail -25; cd ../..
```

Expected: the pinned, overlay, and dragging tests FAIL, because the Task 2 stub returns `true` unconditionally. `idlePanelCollapses` passes. This is the correct starting point.

- [ ] **Step 4: AUTHOR CONTRIBUTION — write the policy**

Replace the stub in `PanelMachine.swift` with the scaffold below, then fill in the body.

```swift
    /// Decides whether the panel is allowed to collapse right now.
    ///
    /// Called twice per collapse: once when the cursor leaves (to decide whether
    /// to arm the exit timer at all) and again when that timer elapses (against a
    /// fresh context, because things may have changed in 350 ms).
    ///
    /// Available signals on `context`:
    ///   - `isPinned`              user pinned it, or summoned it by hotkey
    ///   - `hasOpenOverlay`        a menu, popover, or sheet is open
    ///   - `isDragging`            a drag is in flight
    ///   - `isEditorFocused`       a text editor holds first responder
    ///   - `msSinceLastKeystroke`  milliseconds since last keypress, nil if none
    ///   - `isWindowKey`           the panel is the key window
    ///
    /// `PanelTiming.typingGrace` is 2.0 seconds.
    ///
    /// The trade-off: collapsing eagerly keeps the screen clean but interrupts
    /// you mid-thought; collapsing lazily never interrupts but leaves the panel
    /// loitering over your work. The first three signals are hard requirements
    /// (see CollapsePolicyTests); the last three are judgment.
    ///
    /// Worth deciding explicitly: should a focused editor with no recent typing
    /// keep the panel open indefinitely, or should the grace period win? And is
    /// `isWindowKey` alone enough to suppress, given a panel can be key simply
    /// because you clicked it once?
    static func shouldCollapse(_ context: PanelContext) -> Bool {
        // TODO(author): implement the policy.
        //
        // Return true  => the panel may collapse.
        // Return false => suppress the collapse.
        fatalError("shouldCollapse not implemented")
    }
```

- [ ] **Step 5: Run the full suite and confirm everything passes**

```bash
cd Packages/NotebarCore && swift test 2>&1 | tail -20; cd ../..
```

Expected: all 18 tests pass. If an invariant test fails, the policy contradicts spec section 4.4 — the invariant wins, so adjust the policy.

- [ ] **Step 6: Add policy tests for the judgment calls**

Once the policy is written, add two or three tests that pin down the decisions actually made, so a future change that alters the feel is caught. For example, if a focused editor suppresses collapse indefinitely:

```swift
@Test("a focused editor suppresses collapse even with no recent typing")
func focusedEditorSuppresses() {
    let editing = PanelContext(isEditorFocused: true, msSinceLastKeystroke: 60_000)
    #expect(PanelMachine.shouldCollapse(editing) == false)
}
```

Write whichever tests match the policy chosen. The point is that the decision becomes executable documentation.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "M0.3: collapse suppression policy with invariant tests"
git push origin main
```

---

### Task 4: EdgeZone — cursor geometry

**Files:**
- Create: `Packages/NotebarCore/Sources/NotebarCore/Panel/EdgeZone.swift`
- Test: `Packages/NotebarCore/Tests/NotebarCoreTests/EdgeZoneTests.swift`

**Interfaces:**
- Consumes: `PanelTiming` from Task 2.
- Produces:
  - `enum EdgeProximity { case away, near, inside }`
  - `struct EdgeZone { init(triggerWidth: CGFloat, proximityWidth: CGFloat); func classify(cursor: CGPoint, screen: CGRect) -> EdgeProximity; static func isOutside(cursor: CGPoint, panelFrame: CGRect, slop: CGFloat) -> Bool }`

Task 6 (`CursorMonitor`) consumes both methods.

- [ ] **Step 1: Write the failing tests**

`Packages/NotebarCore/Tests/NotebarCoreTests/EdgeZoneTests.swift`:

```swift
import Testing
import Foundation
@testable import NotebarCore

@Suite("EdgeZone geometry")
struct EdgeZoneTests {

    // A 1920x1080 screen whose origin is at zero, in Cocoa coordinates
    // (origin bottom-left, y increasing upward).
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let zone = EdgeZone(triggerWidth: 2, proximityWidth: 80)

    @Test("a cursor on the far left is away")
    func farLeftIsAway() {
        #expect(zone.classify(cursor: CGPoint(x: 10, y: 500), screen: screen) == .away)
    }

    @Test("a cursor 40pt from the right edge is near")
    func fortyPointsIsNear() {
        #expect(zone.classify(cursor: CGPoint(x: 1880, y: 500), screen: screen) == .near)
    }

    @Test("a cursor 1pt from the right edge is inside the trigger")
    func onePointIsInside() {
        #expect(zone.classify(cursor: CGPoint(x: 1919, y: 500), screen: screen) == .inside)
    }

    @Test("the boundary values are inclusive")
    func boundariesAreInclusive() {
        #expect(zone.classify(cursor: CGPoint(x: 1918, y: 500), screen: screen) == .inside)
        #expect(zone.classify(cursor: CGPoint(x: 1840, y: 500), screen: screen) == .near)
        #expect(zone.classify(cursor: CGPoint(x: 1839, y: 500), screen: screen) == .away)
    }

    @Test("a cursor above or below the screen is away")
    func outsideVerticalBoundsIsAway() {
        #expect(zone.classify(cursor: CGPoint(x: 1919, y: 2000), screen: screen) == .away)
        #expect(zone.classify(cursor: CGPoint(x: 1919, y: -10), screen: screen) == .away)
    }

    @Test("a cursor past the right edge is away, not inside")
    func pastTheEdgeIsAway() {
        // This happens with a second display to the right. The cursor has left
        // this screen entirely and must not keep the trigger armed.
        #expect(zone.classify(cursor: CGPoint(x: 1930, y: 500), screen: screen) == .away)
    }

    @Test("a non-zero screen origin is handled")
    func nonZeroOriginScreen() {
        // A second display placed to the right of the main one.
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        #expect(zone.classify(cursor: CGPoint(x: 3839, y: 500), screen: right) == .inside)
        #expect(zone.classify(cursor: CGPoint(x: 1930, y: 500), screen: right) == .away)
    }

    @Test("the exit slop widens the panel bounds")
    func exitSlopWidensBounds() {
        let panel = CGRect(x: 1500, y: 0, width: 420, height: 1080)
        // 10pt outside the panel, inside a 24pt slop: still counts as in.
        #expect(EdgeZone.isOutside(cursor: CGPoint(x: 1490, y: 500), panelFrame: panel, slop: 24) == false)
        // 30pt outside: genuinely gone.
        #expect(EdgeZone.isOutside(cursor: CGPoint(x: 1470, y: 500), panelFrame: panel, slop: 24) == true)
    }
}
```

- [ ] **Step 2: Run and confirm the tests fail**

```bash
cd Packages/NotebarCore && swift test 2>&1 | tail -10; cd ../..
```

Expected: `cannot find 'EdgeZone' in scope`.

- [ ] **Step 3: Write EdgeZone**

`EdgeZone.swift`:

```swift
import Foundation

public enum EdgeProximity: Equatable, Sendable {
    /// Far from the edge. Poll slowly.
    case away
    /// Close enough to be approaching. Poll fast, but do not arm the dwell.
    case near
    /// Inside the activation strip. Arm the dwell timer.
    case inside
}

/// Classifies a cursor position against a screen's right edge.
///
/// All coordinates are Cocoa screen coordinates: origin bottom-left of the
/// main display, y increasing upward. `NSEvent.mouseLocation` and
/// `NSScreen.frame` both use this space, so no flipping is needed — which is
/// the opposite of most other macOS coordinate work and a classic trap.
public struct EdgeZone: Equatable, Sendable {
    public let triggerWidth: CGFloat
    public let proximityWidth: CGFloat

    public init(triggerWidth: CGFloat, proximityWidth: CGFloat) {
        self.triggerWidth = triggerWidth
        self.proximityWidth = proximityWidth
    }

    public func classify(cursor: CGPoint, screen: CGRect) -> EdgeProximity {
        guard cursor.y >= screen.minY, cursor.y <= screen.maxY else { return .away }

        let distance = screen.maxX - cursor.x

        // Negative means the cursor is past this screen's right edge, which
        // happens when a second display sits to the right. It has left.
        guard distance >= 0 else { return .away }

        if distance <= triggerWidth { return .inside }
        if distance <= proximityWidth { return .near }
        return .away
    }

    /// Whether the cursor has cleared the panel by more than `slop`.
    ///
    /// The slop is what stops the panel collapsing when the cursor drifts a few
    /// points past its edge on the way to a scrollbar (spec section 4.3).
    public static func isOutside(cursor: CGPoint, panelFrame: CGRect, slop: CGFloat) -> Bool {
        !panelFrame.insetBy(dx: -slop, dy: -slop).contains(cursor)
    }
}
```

- [ ] **Step 4: Run and confirm the tests pass**

```bash
cd Packages/NotebarCore && swift test 2>&1 | tail -10; cd ../..
```

Expected: all tests pass (26 total across the three suites).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "M0.4: EdgeZone cursor geometry with multi-display tests"
git push origin main
```

---

### Task 5: EdgePanel — the window

**Files:**
- Create: `Notebar/Panel/EdgePanel.swift`
- Modify: `Notebar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `final class EdgePanel: NSPanel` with `init(contentRect: NSRect)`.

Task 7 (`PanelController`) owns the instance.

This task has no unit test — it is window configuration, verified by looking at it. The verification steps are precise so "looks right" is not a judgment call.

- [ ] **Step 1: Write EdgePanel**

`Notebar/Panel/EdgePanel.swift`:

```swift
import AppKit

/// The floating overlay window.
///
/// `NSPanel` rather than `NSWindow`, and specifically `.nonactivatingPanel`:
/// that style mask is what lets the panel accept keystrokes *without*
/// activating the application, so typing a note does not disturb whatever app
/// the user was actually working in (spec section 4.1).
final class EdgePanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating

        // .fullScreenAuxiliary is what allows appearing over fullscreen apps;
        // .canJoinAllSpaces follows the user across Spaces (spec section 4.1).
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Visibility is owned by PanelController's state machine, not by AppKit.
        hidesOnDeactivate = false
        animationBehavior = .none

        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    // A borderless window refuses key status unless this is overridden, which
    // would make every text field in the panel unusable.
    override var canBecomeKey: Bool { true }

    // Main status would put the panel in the window menu and the app switcher.
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Show it temporarily from AppDelegate to verify**

Replace the body of `applicationDidFinishLaunching` in `Notebar/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: EdgePanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Temporary verification scaffold — replaced by PanelController in Task 7.
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 420
        let frame = NSRect(
            x: screen.visibleFrame.maxX - width,
            y: screen.visibleFrame.minY,
            width: width,
            height: screen.visibleFrame.height
        )
        let panel = EdgePanel(contentRect: frame)
        panel.backgroundColor = NSColor.systemRed.withAlphaComponent(0.35)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 3: Verify the four window behaviours**

```bash
make run
```

Check each, in order:

1. **A translucent red strip appears down the right edge of the screen.** If nothing appears, the panel was deallocated — confirm it is stored in `self.panel`.
2. **No Dock icon and no app menu.** `LSUIElement` is working.
3. **The panel stays visible when you click another app.** `hidesOnDeactivate = false` is working.
4. **Put another app into fullscreen (`⌃⌘F`). The strip remains visible on top.** This is `.fullScreenAuxiliary`. If it disappears, that flag is missing from `collectionBehavior`.

```bash
pkill -x Notebar
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "M0.5: EdgePanel NSPanel subclass with fullscreen-overlay flags"
git push origin main
```

---

### Task 6: CursorMonitor — adaptive polling

**Files:**
- Create: `Notebar/Panel/CursorMonitor.swift`

**Interfaces:**
- Consumes: `EdgeZone`, `EdgeProximity`, `PanelTiming`, `PanelEvent`, `PollRate` from Tasks 2 and 4.
- Produces:
  ```swift
  final class CursorMonitor {
      var onEvent: ((PanelEvent) -> Void)?
      var panelFrame: (() -> CGRect?)?
      func start()
      func stop()
      func setRate(_ rate: PollRate)
  }
  ```

Task 7 (`PanelController`) owns the instance and supplies both closures.

- [ ] **Step 1: Write CursorMonitor**

`Notebar/Panel/CursorMonitor.swift`:

```swift
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
        let cursor = NSEvent.mouseLocation

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                ?? NSScreen.main else { return }

        emitPanelEvents(cursor: cursor)
        emitEdgeEvents(cursor: cursor, screen: screen.frame)
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
            slop: PanelTiming.exitSlop
        )
        defer { wasInsidePanel = isInside }
        guard isInside != wasInsidePanel else { return }

        onEvent?(isInside ? .cursorEnteredPanel : .cursorLeftPanel)
    }
}
```

- [ ] **Step 2: Verify polling works by logging**

Temporarily add to `AppDelegate.applicationDidFinishLaunching`, after the panel is created:

```swift
        let monitor = CursorMonitor()
        monitor.onEvent = { event in NSLog("cursor event: \(event)") }
        monitor.panelFrame = { [weak panel] in panel?.frame }
        monitor.start()
        self.monitor = monitor
```

and a stored property `private var monitor: CursorMonitor?`.

```bash
make run
log stream --predicate 'process == "Notebar"' --style compact
```

Move the cursor to the right edge and away several times.

Expected: `cursorEnteredTrigger` and `cursorLeftTrigger` appear once per crossing, **not** repeatedly while resting at the edge. `cursorEnteredPanel` and `cursorLeftPanel` appear as you move across the red strip's boundary. If events repeat every tick, the transition guard is broken.

```bash
pkill -x Notebar
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "M0.6: CursorMonitor with permission-free adaptive polling"
git push origin main
```

---

### Task 7: PanelController — wiring it together

**Files:**
- Create: `Notebar/Panel/PanelController.swift`
- Modify: `Notebar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `EdgePanel` (Task 5), `CursorMonitor` (Task 6), `PanelMachine`, `PanelState`, `PanelEffect`, `PanelContext`, `PanelTiming` (Tasks 2–3).
- Produces:
  ```swift
  @MainActor final class PanelController {
      init(content: NSView)
      func start()
      func toggle()
      var isPinned: Bool { get set }
  }
  ```

Tasks 8 and 9 call `toggle()`.

**This is the task where the app becomes real.** Everything before it was parts.

- [ ] **Step 1: Write PanelController**

`Notebar/Panel/PanelController.swift`:

```swift
import AppKit
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

    private var state: PanelState = .hidden
    private var context = PanelContext()
    private var timers: [PanelTimer: Timer] = [:]
    private var escapeMonitor: Any?

    private static let panelWidth: CGFloat = 420

    var isPinned: Bool {
        get { context.isPinned }
        set { context.isPinned = newValue }
    }

    init(content: NSView) {
        let initial = NSRect(x: 0, y: 0, width: Self.panelWidth, height: 600)
        panel = EdgePanel(contentRect: initial)
        panel.contentView = content
    }

    func start() {
        monitor.onEvent = { [weak self] event in self?.send(event) }
        monitor.panelFrame = { [weak self] in
            guard let self, self.panel.isVisible else { return nil }
            return self.panel.frame
        }
        monitor.start()
        observeKeyWindow()
        installEscapeMonitor()
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
    private func frames(on screen: NSScreen) -> (onscreen: NSRect, offscreen: NSRect) {
        let area = screen.visibleFrame
        let onscreen = NSRect(
            x: area.maxX - Self.panelWidth,
            y: area.minY,
            width: Self.panelWidth,
            height: area.height
        )
        return (onscreen, onscreen.offsetBy(dx: Self.panelWidth, dy: 0))
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

        animate(to: onscreen, duration: PanelTiming.expandDuration)
    }

    private func hidePanel() {
        guard panel.isVisible, let screen = activeScreen() else { return }
        let (_, offscreen) = frames(on: screen)

        animate(to: offscreen, duration: PanelTiming.collapseDuration) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func animate(
        to frame: NSRect,
        duration: TimeInterval,
        then completion: (() -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            completion?()
            // The reducer decides what "finished" means for the current state.
            self?.send(.animationFinished)
        })
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
```

- [ ] **Step 2: Wire it from AppDelegate with a placeholder content view**

Replace `Notebar/App/AppDelegate.swift` entirely:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Placeholder content, replaced by RootView in Task 8.
        let placeholder = NSHostingView(
            rootView: Color.blue.opacity(0.25).ignoresSafeArea()
        )

        let controller = PanelController(content: placeholder)
        controller.start()
        self.controller = controller
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 3: Verify the full behaviour**

```bash
make run
```

Walk each case:

1. **Move the cursor to the right edge and rest there.** The panel slides out after roughly a tenth of a second.
2. **Move the cursor away.** It slides back after roughly a third of a second — not instantly.
3. **Move to the edge, then immediately away before it opens.** Nothing happens; the dwell timer was cancelled.
4. **Open the panel, move just past its left border by a few points, then back.** It does not collapse — that is `exitSlop`.
5. **Open it, then move away and back before it finishes collapsing.** It reverses smoothly rather than completing the collapse and reopening.
6. **Press Escape while it is open.** It collapses immediately.

If case 2 collapses instantly rather than after a delay, `exitDwell` is not being armed — check that `shouldCollapse` from Task 3 is not returning false at the wrong point.

```bash
pkill -x Notebar
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "M0.7: PanelController wiring machine, monitor, and window"
git push origin main
```

---

### Task 8: Tab rail and the three tabs

**Files:**
- Create: `Notebar/Features/AppTab.swift`
- Create: `Notebar/Features/RootView.swift`
- Create: `Notebar/Features/TabRail.swift`
- Create: `Notebar/Features/Notes/NotesTab.swift`
- Create: `Notebar/Features/Tasks/TasksTab.swift`
- Create: `Notebar/Features/Settings/SettingsTab.swift`
- Create: `Notebar/DesignSystem/Tokens.swift`
- Modify: `Notebar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `struct RootView: View`, used as the panel's content in `AppDelegate`.

- [ ] **Step 1: Write the design tokens**

`Notebar/DesignSystem/Tokens.swift`:

```swift
import SwiftUI

enum Tokens {
    enum Size {
        static let railWidth: CGFloat = 56
        static let railWidthCompact: CGFloat = 44
        /// Below this panel width the rail drops its labels.
        static let compactBreakpoint: CGFloat = 340
        /// Above this the Tasks board becomes side-by-side (M2).
        static let boardBreakpoint: CGFloat = 700
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
    }
}
```

- [ ] **Step 2: Write the tab enum**

`Notebar/Features/AppTab.swift`:

```swift
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case notes
    case tasks
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes:    return "Notes"
        case .tasks:    return "Tasks"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .notes:    return "doc.text"
        case .tasks:    return "checklist"
        case .settings: return "gearshape"
        }
    }
}
```

- [ ] **Step 3: Write the tab rail**

`Notebar/Features/TabRail.swift`:

```swift
import SwiftUI

struct TabRail: View {
    @Binding var selection: AppTab
    let isCompact: Bool

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            ForEach(AppTab.allCases) { tab in
                TabRailButton(
                    tab: tab,
                    isSelected: selection == tab,
                    isCompact: isCompact
                ) {
                    selection = tab
                }
            }
            Spacer()
        }
        .padding(.top, Tokens.Space.md)
        .frame(width: isCompact ? Tokens.Size.railWidthCompact : Tokens.Size.railWidth)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

private struct TabRailButton: View {
    let tab: AppTab
    let isSelected: Bool
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 16, weight: .medium))
                if !isCompact {
                    Text(tab.title)
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.sm)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.Space.xs)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
```

- [ ] **Step 4: Write the three empty tabs**

`Notebar/Features/Notes/NotesTab.swift`:

```swift
import SwiftUI

struct NotesTab: View {
    var body: some View {
        PlaceholderTab(
            symbol: "doc.text",
            title: "Notes",
            detail: "Multiple notes as tabs, arriving in M1."
        )
    }
}
```

`Notebar/Features/Tasks/TasksTab.swift`:

```swift
import SwiftUI

struct TasksTab: View {
    var body: some View {
        PlaceholderTab(
            symbol: "checklist",
            title: "Tasks",
            detail: "A board with statuses you can drag between, arriving in M2."
        )
    }
}
```

`Notebar/Features/Settings/SettingsTab.swift`:

```swift
import SwiftUI

struct SettingsTab: View {
    var body: some View {
        PlaceholderTab(
            symbol: "gearshape",
            title: "Settings",
            detail: "Activation, appearance, and data settings, arriving in M4."
        )
    }
}

/// Shared empty state so all three tabs look deliberate rather than unfinished.
struct PlaceholderTab: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Tokens.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Tokens.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Write RootView**

`Notebar/Features/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @State private var selection: AppTab = .notes

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < Tokens.Size.compactBreakpoint

            HStack(spacing: 0) {
                TabRail(selection: $selection, isCompact: isCompact)

                Divider()

                Group {
                    switch selection {
                    case .notes:    NotesTab()
                    case .tasks:    TasksTab()
                    case .settings: SettingsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
    }
}

#Preview {
    RootView().frame(width: 420, height: 700)
}
```

- [ ] **Step 6: Use it as the panel content**

In `Notebar/App/AppDelegate.swift`, replace the placeholder:

```swift
        let content = NSHostingView(rootView: RootView())
```

- [ ] **Step 7: Verify**

```bash
make run
```

Expected: hovering the right edge reveals a translucent panel with a three-icon rail on the left. Clicking each icon switches the content. The panel is a frosted material rather than flat colour, and text is legible in both light and dark appearance — switch appearance in System Settings and check.

```bash
pkill -x Notebar
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "M0.8: tab rail with three placeholder tabs"
git push origin main
```

---

### Task 9: Menu bar item and global hotkey

**Files:**
- Create: `Notebar/App/StatusItemController.swift`
- Create: `Notebar/App/GlobalHotKey.swift`
- Modify: `Notebar/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `PanelController.toggle()` from Task 7.
- Produces:
  - `final class StatusItemController { init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) }`
  - `final class GlobalHotKey { init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) }`

- [ ] **Step 1: Write the status item**

`Notebar/App/StatusItemController.swift`:

```swift
import AppKit

/// The menu bar presence. With `LSUIElement` there is no Dock icon, so this is
/// the only way to quit the app or summon the panel by mouse.
@MainActor
final class StatusItemController {

    private let item: NSStatusItem

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "sidebar.right",
                accessibilityDescription: "Notebar"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show Notebar",
            action: #selector(MenuTarget.toggle),
            keyEquivalent: ""
        )
        let quit = NSMenuItem(
            title: "Quit Notebar",
            action: #selector(MenuTarget.quit),
            keyEquivalent: "q"
        )

        let target = MenuTarget(onToggle: onToggle, onQuit: onQuit)
        toggle.target = target
        quit.target = target
        // The menu holds the only strong reference to the target.
        self.target = target

        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu
    }

    private var target: MenuTarget?
}

/// NSMenuItem actions need an Objective-C target, which a Swift closure cannot be.
private final class MenuTarget: NSObject {
    private let onToggle: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
    }

    @objc func toggle() { onToggle() }
    @objc func quit() { onQuit() }
}
```

- [ ] **Step 2: Write the global hotkey**

`Notebar/App/GlobalHotKey.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Carbon is ancient, but it is the only permission-free way to register a
/// global hotkey on macOS — `NSEvent.addGlobalMonitorForEvents` for key events
/// requires Accessibility permission, which spec section 1 rules out. Every
/// launcher app on the platform does this.
@MainActor
final class GlobalHotKey {

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    fileprivate static var callbacks: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `UInt32(kVK_Space)`.
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(cmdKey | shiftKey)`.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.callbacks[id] = handler
        Self.installHandlerIfNeeded()

        // 'NBR1' as a four-character code.
        let hotKeyID = EventHotKeyID(signature: 0x4E42_5231, id: id)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            NSLog("GlobalHotKey: registration failed with status \(status)")
            Self.callbacks[id] = nil
            return nil
        }
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        GlobalHotKey.callbacks[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            nil
        )
    }
}

/// A free function, because `InstallEventHandler` takes a C function pointer,
/// which a Swift method or capturing closure cannot be.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GlobalHotKey.callbacks[id]?()
        }
    }
    return noErr
}
```

- [ ] **Step 3: Wire both from AppDelegate**

Replace `Notebar/App/AppDelegate.swift` entirely:

```swift
import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = PanelController(content: NSHostingView(rootView: RootView()))
        controller.start()
        self.controller = controller

        statusItem = StatusItemController(
            onToggle: { [weak controller] in controller?.toggle() },
            onQuit: { NSApp.terminate(nil) }
        )

        // Cmd+Shift+Space
        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak controller] in
            controller?.toggle()
        }

        if hotKey == nil {
            NSLog("Notebar: global hotkey unavailable — another app may hold Cmd+Shift+Space")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 4: Verify**

```bash
make run
```

Check each:

1. **A sidebar icon appears in the menu bar.** Clicking it shows the menu.
2. **"Show Notebar" opens the panel** even with the cursor nowhere near the edge.
3. **`Cmd+Shift+Space` from inside another app toggles the panel.** No permission prompt appears at any point — if macOS asks for Accessibility access, something is using a global event monitor and must be found and removed.
4. **"Quit Notebar" quits.**

- [ ] **Step 5: Run the full check before finishing**

```bash
make check && make test && make build
```

Expected: purity OK, all tests pass, build succeeds.

- [ ] **Step 6: Commit and tag M0**

```bash
git add -A
git commit -m "M0.9: menu bar item and permission-free global hotkey"
git tag -a m0-shell -m "M0: panel shell complete"
git push origin main --tags
```

---

## M0 Definition of Done

- [ ] Cursor resting at the right screen edge expands the panel in under 250 ms.
- [ ] Moving away collapses it after the exit dwell, not instantly.
- [ ] Brushing the edge without resting does not open it.
- [ ] Drifting a few points off the panel does not collapse it.
- [ ] Returning mid-collapse reverses smoothly.
- [ ] Escape collapses immediately.
- [ ] `Cmd+Shift+Space` toggles from any app.
- [ ] The panel appears over a fullscreen app.
- [ ] No Dock icon; the menu bar item quits the app.
- [ ] **No permission prompt has appeared at any point.**
- [ ] `make check && make test && make build` is clean.
- [ ] Idle CPU under 1% (check in Activity Monitor with the panel closed).

## Self-Review Notes

**Spec coverage.** Section 4.1 window config → Task 5. Section 4.2 cursor polling → Tasks 4 and 6. Section 4.3 state machine and timings → Tasks 2 and 4. Section 4.4 suppression → Task 3. Section 6.1 tab rail → Task 8. Section 3 rules 1 and 2 → Tasks 1 and 2. Section 7 M0 scope: status item and hotkey → Task 9. No M0 requirement is unassigned.

**Deviation from the spec's file layout, recorded deliberately.** The spec places `PanelMachine.swift` under `Notebar/Panel/`. This plan puts it in `Packages/NotebarCore/` instead. The spec's actual requirement — that it import no AppKit — is better served there, because the package boundary enforces it mechanically and its tests run via `swift test` in about a second with no Xcode involved. `EdgeZone` and `PanelTiming` move for the same reason.

**Type consistency check.** `PanelMachine.reduce` and `PanelMachine.shouldCollapse` are referenced with those exact names in Tasks 2, 3, and 7. `PanelContext` field names are identical across Tasks 2, 3, and 7. `CursorMonitor.setRate` is defined in Task 6 and called in Task 7. `PanelController.toggle()` is defined in Task 7 and called in Task 9. `EdgeZone.isOutside` is defined in Task 4 and called in Task 6.

**Known risk.** `MainActor.assumeIsolated` inside `Timer` and notification closures is correct under Swift 5 language mode with minimal concurrency checking, which is what the global constraints specify. If concurrency checking is ever raised, these become the first places to revisit.
