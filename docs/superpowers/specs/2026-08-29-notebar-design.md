# Notebar — Design Spec

- **Date:** 2026-08-29
- **Status:** Draft, pending approval
- **Stack:** Swift 6.3 · SwiftUI + AppKit · SQLite (GRDB)
- **Platform:** macOS 26+ first; Windows later as a separate shell over a shared core

---

## 1. Purpose

Notebar is an always-available scratch surface that lives at the right edge of the
screen. It stays invisible until the cursor reaches the edge, then slides out as a
floating overlay above whatever app is in front — including fullscreen apps. It holds
notes and tasks that can reference each other, so a thought captured while working can
become a tracked task without leaving the current context.

The design goal is **zero-friction capture**. Anything that makes the user think about
Notebar as an application — activating it, hunting for its window, losing their place —
is a defect.

### Success criteria

1. Cursor reaches the edge, panel fully expanded and usable, in under 300 ms — of which
   at most 180 ms is animation. The remainder is `edgeDwell` (section 4.3), the deliberate
   pause that stops the panel firing when the cursor is merely crossing to a scrollbar.
   All three numbers become user settings in M4, so this is a tuned default rather than a
   fixed constraint.
2. Capturing a note from any app requires no click on any window but Notebar's.
2a. When collapsed, a small handle remains visible at the right edge showing the icon of
   the currently selected tab, so the panel's location and current context are always
   discoverable without hovering.
3. The panel never collapses while the user is mid-thought — typing, dragging, or with a
   menu open.
4. **Idle cost under 1% CPU and under 100 MB resident.** This is a hard requirement, not
   an aspiration; it is the reason the stack is native.
5. No permission prompt on first launch.

### Non-goals for v1

Cloud sync, multi-device, sharing, collaboration, mobile, plugins, AI features, calendar
integration, reminders. The schema is designed not to preclude sync; nothing is built
for it.

---

## 2. Stack decision

The author is fluent in TypeScript and Node and does not know Swift, SwiftUI, or AppKit.
The stack was nonetheless chosen as native, deliberately, after considering the
alternative.

**The argument for Electron** was that it keeps every line of the app — including the
difficult window and cursor code — in a language the author already writes. That is a
real advantage and it was the initial recommendation.

**The argument that won** is that Notebar is an always-running utility whose entire
premise is weightlessness. An app that claims to be invisible until needed, while
holding ~250 MB resident all day, contradicts its own pitch in a way no benchmark
captures. A runtime floor is permanent; unfamiliarity with a language is temporary.

The Electron memory reputation is often mis-attributed — Teams is heavy because Teams is
enormous, and "grows over hours" is usually a leak in an app's own JavaScript rather than
anything intrinsic to the framework. But that only establishes that Electron *could* be
acceptable with sustained discipline, which is a worse guarantee than being lightweight
by construction.

| Candidate | Idle RAM | Hard parts in | Windows path | Verdict |
|---|---|---|---|---|
| **SwiftUI + AppKit** | ~60 MB | Swift/AppKit, ~230 bounded lines | Shell rewrite over a shared core | **Selected** |
| Tauri v2 | ~80 MB | Rust, plus a third-party plugin for macOS panel semantics | Good | Rejected — no Rust toolchain; a second unknown language stacked on native semantics |
| Electron | ~250 MB | TypeScript (all first-party) | Free | Rejected — runtime floor contradicts the product premise |

### Why the unfamiliarity risk is acceptable

The AppKit surface for this app is bounded and small — three files, roughly 230 lines,
written once and rarely revisited:

| File | Purpose | Approx. |
|---|---|---|
| `EdgePanel.swift` | `NSPanel` subclass and window flags | 80 |
| `HotEdgeMonitor.swift` | Cursor polling timer | 90 |
| `StatusItemController.swift` | Menu bar item | 60 |

Everything else is SwiftUI, which maps closely onto the React model the author already
uses. §10 is an onboarding section that makes that mapping explicit.

### Toolchain

| Concern | Choice | Why |
|---|---|---|
| Language | Swift 6.3, **Swift 5 language mode**, minimal concurrency checking | Strict concurrency in Swift 6 mode buries newcomers in `Sendable` and actor-isolation diagnostics unrelated to their actual bug. Tightened after the app exists. |
| UI | SwiftUI, with AppKit via `NSViewRepresentable` where required | Declarative and close to the author's mental model. |
| Window | `NSPanel` (AppKit) | SwiftUI has no equivalent for non-activating floating panels. |
| Database | SQLite via GRDB | Mature, well documented, excellent FTS5 support. |
| Rich text | `NSTextView` behind a SwiftUI wrapper | The known-good path; see §6.2. |
| Packaging | Xcode, hardened runtime, notarized | Standard distribution. |
| Tests | Swift Testing (unit) + XCUITest (thin E2E) | Core is pure Swift and testable without a host app. |

### Decisions made on the author's behalf

Each is reversible and flagged for review.

1. **Board columns are data, not an enum.** Seeded with Queue / Working / Done, stored as
   rows, so user-defined statuses in v2 need no migration.
2. **Note content persists as RTF plus a plain-text shadow column.** RTF round-trips
   natively through `NSAttributedString` and is readable by other applications; the shadow
   column feeds full-text search.
3. **Open note tabs persist across restarts.** Matches the Notepad++ mental model the
   author referenced — the session is part of the state.
4. **The Tasks board adapts to panel width** — stacked status groups when narrow,
   side-by-side kanban when wide. See §6.3.
5. **Swift 5 language mode initially**, as described above.

---

## 3. Architecture

```
Notebar/
├── Notebar.xcodeproj
├── Notebar/                        app target · AppKit + SwiftUI · macOS-only
│   ├── App/
│   │   ├── NotebarApp.swift        @main, LSUIElement, environment wiring
│   │   ├── AppDelegate.swift       lifecycle, single-instance
│   │   ├── StatusItemController.swift
│   │   └── LaunchAtLogin.swift
│   ├── Panel/
│   │   ├── EdgePanel.swift         NSPanel subclass + window flags
│   │   ├── HotEdgeMonitor.swift    cursor polling
│   │   ├── PanelMachine.swift      PURE — no AppKit import
│   │   └── PanelController.swift   wires monitor + machine + panel
│   ├── Features/
│   │   ├── Notes/                  NotesTab, TabStrip, NoteEditor, QuickOpen
│   │   ├── Tasks/                  TasksTab, BoardLayout, GroupedLayout, TaskCard
│   │   └── Settings/               SettingsTab (shell only in v1)
│   ├── Linking/                    MentionPopover, LinkChip, BacklinksView
│   └── DesignSystem/               Tokens, Chrome, Buttons, EmptyStates
└── Packages/NotebarCore/           PURE SWIFT · zero AppKit / SwiftUI imports
    ├── Models/                     Note, Task, Board, BoardColumn, Link, Tag, OpenTab
    ├── Store/                      Schema, Migrations, Repository protocols, GRDB impls
    ├── Search/                     SearchIndex (FTS5)
    └── Linking/                    LinkGraph, BacklinkResolver
```

### Three rules that carry the architecture

**1. `NotebarCore` never imports `AppKit`, `SwiftUI`, or `UIKit`.** This is the Windows
strategy expressed as one enforceable constraint, checked in CI and by a pre-commit hook:

```bash
! grep -rE '^import (AppKit|SwiftUI|UIKit)' Packages/NotebarCore/Sources/
```

Swift compiles on Windows officially, so a core with no Apple-UI dependency is genuinely
portable. One caveat is recorded honestly: **GRDB targets Apple platforms and Linux, not
Windows.** Storage therefore sits behind repository protocols (`NoteRepository`,
`TaskRepository`, `LinkRepository`) with GRDB as the macOS implementation, so a Windows
port swaps the implementation rather than rewriting call sites.

**2. `PanelMachine.swift` imports nothing from AppKit.** The panel's behaviour — the code
most likely to produce subtle, hard-to-reproduce bugs — is a pure function:

```swift
func reduce(_ state: PanelState, _ event: PanelEvent, _ ctx: PanelContext)
  -> (PanelState, [PanelEffect])
```

Every flicker scenario becomes an ordinary table-driven unit test rather than something
reproduced by waving a mouse at the screen. `PanelController` is the only code that turns
`[PanelEffect]` into real window calls.

**3. AppKit is quarantined.** Outside `Panel/`, `StatusItemController`, and the editor
wrapper, the app is SwiftUI. This keeps the unfamiliar surface small and stable.

---

## 4. The panel

### 4.1 Window configuration

An `NSPanel` subclass, created once at launch and hidden rather than destroyed, so
expansion never pays window-creation cost.

| Property | Value | Why |
|---|---|---|
| geometry (expanded) | 340 pt wide, 70% of `visibleFrame.height`, vertically centred, flush to the right edge |
| geometry (collapsed) | 30 pt wide, 56 pt tall, vertically centred, flush right — a handle showing the active tab's icon |
| `styleMask` | `[.nonactivatingPanel, .borderless, .fullSizeContentView]` | `.nonactivatingPanel` is the key flag: it lets the panel accept keystrokes **without activating the application**, so typing into the overlay does not disturb the frontmost app. |
| `level` | `.floating` | Above normal windows, below system UI. |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | `.fullScreenAuxiliary` is what allows appearing over fullscreen apps; `.canJoinAllSpaces` follows the user across Spaces. |
| `hidesOnDeactivate` | `false` | Visibility is owned by the state machine, not AppKit. |
| `isFloatingPanel` | `true` | Panel semantics. |
| `isMovableByWindowBackground` | `false` | Position is owned by the edge dock. |

The app is `LSUIElement` — no Dock icon, no menu bar of its own. An `NSStatusItem`
provides quit, settings, and a manual toggle.

### 4.2 Hot edge detection

```
Timer on the main run loop, .common mode
  └── NSEvent.mouseLocation      ← static property; NO permission, NO entitlement
        ├── idle       10 Hz     cursor far from any edge
        └── near edge  60 Hz     cursor within 80 pt of the active screen's right edge
```

`NSEvent.mouseLocation` requires no Accessibility or Input Monitoring permission. This is
precisely why the fully invisible activation is viable with no first-run prompt — a
global event monitor (`NSEvent.addGlobalMonitorForEvents`) would have been the obvious
approach and would have dragged a permission dialog in with it.

A plain `Timer` is used rather than `CVDisplayLink`: polling is not display-synchronized
work, and `.common` run-loop mode keeps it firing while menus and drags are tracking —
exactly the moments the panel must stay responsive.

The active screen is the one whose frame contains the cursor, so multi-monitor works by
construction. Only that screen's right edge triggers in v1; edge and screen selection
become settings later.

**The trigger band matches the panel, not the screen.** Because the panel is 70% of the
screen height and vertically centred, the armed strip covers only that same vertical band
rather than the full edge. Without this, touching the edge near the top of the screen
would open a panel centred well below the cursor, `CursorMonitor` would immediately report
`.cursorLeftPanel`, and the panel would collapse 350 ms after appearing — the state machine
behaving exactly as specified while the result looked like a flicker bug. `EdgeZone.classify`
already guards on the passed rect's y-bounds, so this needs no change to that type: the
controller simply passes the panel's band in place of the screen frame.

**Known limits.** Polling cannot observe the cursor while another application holds an
exclusive pointer grab (some fullscreen games). This degrades to "the panel does not
open," which is acceptable; the global hotkey remains available in every case.

### 4.3 State machine

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
   ┌─────────┐  edge dwell   ┌───────────┐  anim done  │
   │ hidden  │──────────────▶│ expanding │────────────▶│
   └─────────┘   ≥120 ms     └───────────┘             │
        ▲                                              ▼
        │                                       ┌────────────┐
        │                          pin ────────▶│  expanded  │
        │                                       └────────────┘
        │                                          │      ▲
        │                          exit dwell      │      │ re-entry
        │                          ≥350 ms         ▼      │ cancels
   ┌────────────┐   anim done   ┌────────────┐            │
   │  hidden    │◀──────────────│ collapsing │────────────┘
   └────────────┘               └────────────┘
```

`pinned` is a flag on `expanded`, not a separate state; it suppresses every collapse
trigger except explicit unpin or `Esc`.

**`hidden` means collapsed-to-handle, not gone.** The window is never ordered out. In the
`hidden` state the panel animates down to a 30x56 handle at the right edge showing the
active tab's icon; expanding animates it back up to full size. The state machine is
unchanged — the same four states and the same events — only the frame that `hidePanel`
animates toward differs.

This removes a whole class of defect rather than adding one. With `orderOut` gone, a stale
animation completion can no longer yank a reopened panel off screen, and the panel can no
longer end up logically expanded while invisible. It also makes the app discoverable: the
handle is a visible affordance, so a new user does not have to be told where to hover.

The armed trigger band still spans the panel's full expanded height rather than just the
handle, so the handle is a target you can aim at but never have to hit precisely.

**Timings** — all surfaced in Settings later:

| Constant | Default | Meaning |
|---|---|---|
| `edgeDwell` | 120 ms | Cursor must rest in the trigger zone this long before expanding. Prevents accidental opens when reaching for a scrollbar. |
| `triggerWidth` | 30 pt | Width of the activation strip, equal to `handleWidth` so hovering the visible handle arms the panel. Was 2 pt, which made the app's only visible affordance a non-target. `edgeDwell` is the accident guard, not a narrow strip. |
| `exitSlop` | 24 pt | Cursor must clear the panel bounds by this margin before the exit timer starts. |
| `exitDwell` | 350 ms | Cursor must remain outside this long before collapsing. |
| `expandDuration` | 180 ms | Slide-in. |
| `collapseDuration` | 140 ms | Slightly faster out than in — reads as responsive rather than sluggish. |

### 4.4 Collapse suppression

This is the difference between a panel that feels alive and one that feels hostile. The
naive implementation collapses on mouse-exit and is unusable in practice: the panel
vanishes when the user reaches for a menu, drags a card, or glances away mid-sentence.

Collapse is suppressed while **any** of these hold:

| Signal | Source |
|---|---|
| `isPinned` | User toggled pin, or summoned via hotkey |
| `hasOpenOverlay` | A menu, popover, or sheet is open |
| `isDragging` | A drag is in flight |
| `isEditorFocused` | A text editor holds first responder |
| `msSinceLastKeystroke` | Typing activity |
| `isWindowKey` | The panel is the key window |

The exact policy is a workflow judgment rather than a technical one, and is left for the
author to write — see §9.

---

## 5. Data model

SQLite via GRDB. Schema shown as SQL for clarity; the source of truth is
`Packages/NotebarCore/Sources/Store/Schema.swift`.

```sql
CREATE TABLE note (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL DEFAULT '',
  body_rtf     BLOB,                      -- NSAttributedString RTF round-trip
  body_plain   TEXT NOT NULL DEFAULT '',  -- shadow column, derived on save
  is_pinned    INTEGER NOT NULL DEFAULT 0,
  sort_order   REAL    NOT NULL,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE board (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, sort_order REAL NOT NULL
);

CREATE TABLE board_column (
  id         TEXT PRIMARY KEY,
  board_id   TEXT NOT NULL REFERENCES board(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL,               -- backlog | active | done
  sort_order REAL NOT NULL,
  wip_limit  INTEGER
);

CREATE TABLE task (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  detail_rtf   BLOB,
  detail_plain TEXT NOT NULL DEFAULT '',
  column_id    TEXT NOT NULL REFERENCES board_column(id),
  sort_order   REAL NOT NULL,
  priority     INTEGER NOT NULL DEFAULT 0,
  due_at       TEXT,
  completed_at TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE link (
  id         TEXT PRIMARY KEY,
  src_type   TEXT NOT NULL,               -- note | task
  src_id     TEXT NOT NULL,
  dst_type   TEXT NOT NULL,
  dst_id     TEXT NOT NULL,
  kind       TEXT NOT NULL DEFAULT 'references',
  created_at TEXT NOT NULL,
  UNIQUE (src_type, src_id, dst_type, dst_id, kind)
);
CREATE INDEX idx_link_src ON link(src_type, src_id);
CREATE INDEX idx_link_dst ON link(dst_type, dst_id);   -- backlinks

CREATE TABLE tag (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE);
CREATE TABLE note_tag (note_id TEXT, tag_id TEXT, PRIMARY KEY (note_id, tag_id));
CREATE TABLE task_tag (task_id TEXT, tag_id TEXT, PRIMARY KEY (task_id, tag_id));

CREATE TABLE open_tab (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, ref_id TEXT NOT NULL,
  sort_order REAL NOT NULL, is_active INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE VIRTUAL TABLE note_fts USING fts5(title, body_plain, content='note', content_rowid='rowid');
CREATE VIRTUAL TABLE task_fts USING fts5(title, detail_plain, content='task', content_rowid='rowid');
```

### Why one generic `link` table

A typed edge table covers note→task, task→note, note→note and task→task with a single
schema, and backlinks are the reverse query on `idx_link_dst`. The alternative —
per-pair join tables — multiplies with every new linkable entity and turns "everything
that references this" into a union across N tables. Retrofitting this later is the single
most expensive change in the design, which is why it is here on day one.

### Why `sort_order REAL`

Fractional ordering. Dropping a card between two others assigns the midpoint of their
orders, so a reorder is one row update instead of renumbering the column. A compaction
pass renormalizes when gaps approach float precision.

### Why RTF plus a plain shadow column

`body_rtf` gives WYSIWYG fidelity and round-trips natively through `NSAttributedString`
with no third-party dependency. `body_plain` is derived on every save and is what FTS5
indexes, so search never parses a blob. RTF is also readable by other applications, so
the content is not locked inside an Apple archive format.

---

## 6. Feature design

### 6.1 Application tab rail (left)

**Control row, top-anchored.** Above the three tabs and separated from them by a hairline
sits a single 56x32pt row holding **two 24x24pt toggles** side by side with a 4pt gap:
**pin** on the left, **maximize** on the right. They are deliberately smaller and
unlabelled so the row does not read as a fourth tab — these change the panel's *behaviour
and size*, not its content.

**Maximize** switches the expanded panel between two sizes:

| Mode | Geometry |
|---|---|
| Normal (default) | 340 pt wide, 70% of `visibleFrame.height`, vertically centred |
| Maximized | **half of `visibleFrame.width`, full `visibleFrame.height`** |

Both are flush to the right edge and keep the left-rounded / right-square corner treatment.
Glyph is `arrow.up.left.and.arrow.down.right` normally, `arrow.down.right.and.arrow.up.left`
when maximized, `accent` in that state.

Maximizing crosses the 700 pt wide breakpoint on any ordinary display, which is what finally
makes the Tasks board's side-by-side kanban layout (§6.3) reachable — at the default 340 pt
it can only ever render as stacked groups.

Maximize is **independent of pin**: a maximized panel still collapses on cursor exit unless
pinned. The two controls sit together precisely so that "work in this for a while" is one
gesture away from "and don't take it away from me".

The pin toggle itself: a 15pt `pin` glyph in `text.secondary`. Active, it becomes
`pin.fill` in `accent`. Toggling it drives `PanelContext.isPinned`, which
`PanelMachine.shouldCollapse` already treats as an absolute veto — a pinned panel ignores
cursor exit, the exit dwell, and every other collapse trigger. Only an explicit unpin or
`Esc` closes it (spec section 4.3).

The pin is deliberately not a fourth tab: it is smaller, unlabelled, and separated by a
rule, because it changes the panel's *behaviour* rather than its content.

The state machine has supported this since M0 — `isPinned` is one of the six suppression
signals in section 4.4 and is already honoured by the reducer. Only the control was missing.

**Collapse button, bottom-anchored.** A 56x32pt control pinned to the bottom of the rail,
separated by a hairline: a 15pt `chevron.right.2` glyph in `text.secondary`, `accent` on
hover. It collapses the panel immediately, without the user having to move the cursor off it.

The case it exists for: the panel is **pinned** and the user is working in it, then wants it
gone *now*. Pinning deliberately defeats every cursor-driven collapse, so before this
control the only ways out were Escape, the menu bar item, or the global hotkey — all of
which require leaving the mouse. A pinned panel should not be harder to dismiss than an
unpinned one.

It reuses the existing `.toggleRequested` event, which the reducer already handles
independently of `shouldCollapse` — so like Escape it overrides pin, and needs no state
machine change. **Pin state is preserved**: collapsing does not unpin, so the next expand is
still pinned. Pin is a preference about behaviour, not a lock on the current appearance.

A ~56 pt vertical rail: Notes, Tasks, Settings. Icon with label beneath at default width;
icon-only below 340 pt. The selected tab persists in `app_state` and is what the panel
shows on its next expand, so the panel resumes where the user left it.

### 6.2 Notes

A horizontal tab strip across the top of the content area, Notepad++ style: click to
switch, drag to reorder, middle-click or `⌘W` to close, `⌘T` for a new note. The strip
scrolls horizontally with an overflow chevron listing hidden tabs — necessary because at
420 pt only three or four tabs fit.

**Editor.** The implementation wraps `NSTextView` in an `NSViewRepresentable` behind the
`NoteEditorView` interface — the seam the plain-text placeholder was built behind precisely
so this swap costs one file. Storage moves from `body` as `String` to `body_rtf` as an RTF
blob, with `body_plain` regenerated in the same transaction so FTS cannot drift (§5).
Lists use `NSTextList`, which `NSTextView` renders and RTF round-trips natively. This is chosen over SwiftUI's `TextEditor` with an
`AttributedString` binding because `NSTextView` gives full control over attributes,
attachments, and first-responder behaviour — all of which the link chips in §6.4 require.
A spike in M1 evaluates whether the SwiftUI-native path is sufficient; because both sit
behind one interface, the outcome does not affect any other part of the design.

Open tabs are rows in `open_tab`, so the session survives a restart. `⌘P` opens quick
search across `note_fts` and `task_fts`. Saves are debounced at 400 ms and on blur;
`body_plain` is regenerated in the same transaction that writes `body_rtf`, so the search
index cannot drift.

### 6.2b Formatting bar

A **32pt row directly beneath the tab toolbar**, visible only while a note is open, with a
1px `border.separator` hairline beneath it. Left-aligned, 28x28pt hit targets, 15pt glyphs
in `text.secondary`, `accent` when the caret sits inside that style:

| Control | Glyph | Shortcut |
|---|---|---|
| Bold | `bold` | `⌘B` |
| Italic | `italic` | `⌘I` |
| Inline code | `chevron.left.forwardslash.chevron.right` | `⌘⇧C` |
| Heading 1 | `textformat.size.larger` | `⌘⌥1` |
| Heading 2 | `textformat.size` | `⌘⌥2` |
| Bulleted list | `list.bullet` | `⌘⇧8` |
| Numbered list | `list.number` | `⌘⇧7` |
| Checklist | `checklist` | `⌘⇧9` |

Buttons **toggle** — pressing Bold with the caret already inside bold text removes it — and
reflect the caret's current state, so the bar doubles as an indicator of where you are.

At 340pt eight 28pt targets fill roughly 224pt, which fits. Below the compact breakpoint
the bar scrolls horizontally rather than wrapping to a second row: chrome must not grow
taller as the panel narrows.

**Why a persistent bar rather than a popover.** Formatting in a notes app is frequent, and
a popover costs a click per use and hides the caret's current state. 32pt of chrome is the
cheaper trade. Markdown-style input shortcuts (`- ` for a bullet, `1. ` for a number) are
supported *in addition*, not instead — discoverability and speed are different needs.

### 6.3 Tasks

A Jira board in a narrow panel needs a layout that adapts to width:

```
  panel < 700 pt                       panel ≥ 700 pt
  ┌────────────────────────┐           ┌──────────────────────────────────────┐
  │ ▼ Queue           (4)  │           │  Queue      Working       Done       │
  │   ┌──────────────────┐ │           │ ┌────────┐ ┌────────┐  ┌────────┐    │
  │   │ Fix edge flicker │ │           │ │ Fix    │ │ Panel  │  │ Schema │    │
  │   ├──────────────────┤ │           │ │ edge   │ │ anim   │  │ draft  │    │
  │   │ Schema review    │ │           │ ├────────┤ ├────────┤  ├────────┤    │
  │   └──────────────────┘ │           │ │ Schema │ │ Tab    │  │ Spike  │    │
  │ ▼ Working         (2)  │           │ │ review │ │ strip  │  │ RTF    │    │
  │   ┌──────────────────┐ │           │ └────────┘ └────────┘  └────────┘    │
  │   │ Panel animation  │ │           │                                      │
  │   └──────────────────┘ │           │                                      │
  │ ▶ Done            (7)  │           │                                      │
  └────────────────────────┘           └──────────────────────────────────────┘
   collapsible status groups            true side-by-side kanban
   drag between groups                  drag between columns
```

Both layouts share one drag coordinator, one drop-target model, and one reorder
operation — only the arrangement differs. Dropping a card writes `column_id` and a
fractional `sort_order`; a drop into a `done`-kind column stamps `completed_at`, and
dragging back out clears it.

A drag in flight suppresses collapse for its whole duration (§4.4). A drag released
outside the panel is cancelled, not dropped.

### 6.3a Task interaction

**Click a card to expand it in place.** The card grows to reveal an editable `detail`
field plus its metadata; clicking its header again collapses it, and expanding another
card collapses the first. **Only one card is expanded at a time** — this is what keeps
switching cheap: every other card stays visible and one click away, so the user never
navigates away from the board to read a task.

**The expanded detail is capped at 200pt and scrolls internally.** Without a cap, a long
detail would push the remaining groups far down the list and the board would stop being a
board. With it, expanding a card in Queue shifts what follows by a bounded amount.

**The detail is always editable** — click into it and type, saved on a 400 ms pause and on
blur, exactly as note bodies already behave. No edit mode and no save button: a second
interaction model for the same act of typing would be a worse cost than the occasional
stray keystroke, and `shouldCollapse` already refuses to collapse a panel with a focused
editor.

Inline expansion rather than the detail sheet §9 frame 18 describes: that sheet is 380pt
wide and the panel's default width is 340pt, so a sheet cannot fit without either
shrinking below its own spec or forcing the user to maximise first. Expanding in place
works at every width, keeps the rest of the board visible for context, and avoids a modal
layer over a panel that is already an overlay. The sheet may return at the wide breakpoint
later; it is not the primary interaction.

**Rename** is inline on the card title — double-click, or Rename from the right-click
menu — matching how note tabs behave. **Delete** is on the same right-click menu.

**Drag a card between groups** to change its status. The drop writes the new `column_id`
and a fractional `sort_order` midway between its new neighbours; dropping into a
`done`-kind column stamps `completed_at`, and dragging back out clears it.

**Dragging is the last unfed collapse-suppression signal.** `PanelContext.isDragging` has
been wired from `PanelViewModel` since the collapse-policy work and nothing has ever set
it. A drag must set it, or the panel can collapse mid-drag when the cursor strays past the
edge — losing the card and the gesture together. `PanelMachine.shouldCollapse` already
treats it as a hard invariant, so this needs a producer, not a reducer change.

### 6.4 Linking

- Typing `@` in a note or task detail opens an autocomplete popover over notes and tasks,
  ranked by recency then FTS relevance. Selecting one inserts a **link chip** — an
  attributed run carrying a custom attribute holding the target's type and id — and writes
  a `link` row in the same transaction.
- Dragging a task card onto an open note inserts a chip at the drop point.
- Every note and task shows a **Backlinks** section listing inbound references: one query
  on `idx_link_dst`.
- Clicking a chip opens the target — notes as a new tab, tasks as a detail sheet.
- Deleting an entity soft-deletes it; existing chips render as tombstones rather than
  silently deleting text the user wrote.

### 6.2a All-notes menu

Immediately **left of the `+`** in the Notes toolbar sits a 28x28pt button with a 15pt
`chevron.down` glyph. Clicking it opens a popover listing **every note**, not just the ones
whose tabs are hidden by overflow — ordered by most recently updated, showing each note's
title and a relative timestamp, with the currently open ones marked.

Selecting a row opens that note as the active tab, creating the tab if it was closed.

**Why all notes rather than an overflow list.** Closing a tab does not delete its note, so
without this there is no route back to a closed note at all — the note still exists in the
database and is unreachable. An overflow-only chevron would leave that gap open. This also
removes the need to scroll a long tab strip hunting for something.

**This is the first real producer of `hasOpenOverlay`.** That signal has been wired through
`PanelViewModel` into `PanelContext` since the collapse-policy work but nothing has ever set
it. While the popover is open the panel must not collapse, or the list would vanish as the
user reaches for it — `PanelMachine.shouldCollapse` already treats `hasOpenOverlay` as a
hard invariant, so this needs no reducer change, only a producer.

### 6.4a Tab toolbar

Every content tab opens with the same 36pt toolbar: context on the left, primary action on
the right, hairline beneath. Notes puts its tab strip on the left and `+ new note` on the
right; Tasks puts its title and count on the left and `+ new task` on the right; Settings
has a title and no action. A new task lands in the first `backlog`-kind column and is moved
by dragging.

One fixed location for the primary action beats a contextually smarter one that moves: the
user should never have to look for it.

### 6.5 Settings

**Appearance → Theme** is Settings' first real control: a three-way choice between
**System** (default), **Light**, and **Dark**, rendered as a segmented picker.

- **System** follows macOS's own appearance and changes live when the user switches it,
  including on the automatic day/night schedule. This is the default because an overlay
  that floats above other apps should match them.
- **Light** and **Dark** override it and stay put.

Applied by setting `NSApp.appearance` to `NSAppearance(named: .aqua)` / `.darkAqua`, or
`nil` for System. Every colour in the app already resolves through semantic tokens
(§1.1–1.2 define both palettes), so this needs no per-view restyling — that is what the
two token modes were built for.

The choice persists in the `app_state` table (§5) rather than `UserDefaults`, keeping one
storage story for everything the app remembers, and is applied at launch before the panel
is first presented so there is no visible flash of the wrong appearance.



Shell only in v1. The tab renders placeholder sections the design already implies —
Activation (edge, dwell timings, hotkey), Appearance (width, theme, material), Data
(database location, export), General (launch at login) — so filling them in later is
wiring, not design.

---

## 7. Milestones

Each milestone ends in a commit and push, per the workspace checkpoint rule.

**M0 — Shell.** Xcode project, `NSPanel` with window flags, hot edge monitor, state
machine with suppression, tab rail, three empty tabs, status item, global hotkey.
Deliberately first: if the panel does not feel right, nothing downstream matters.

**M1 — Notes.** `NotebarCore` skeleton, schema and migrations, repositories, editor spike
and decision, tab strip, open-tab persistence, FTS search, quick open.

**M2 — Tasks.** Board and column seeding, task CRUD, both layouts, drag coordinator,
fractional reordering with compaction, completion stamping.

**M3 — Linking.** `@` autocomplete, link chips, `link` writes, backlinks, drag-to-link,
tombstones.

**M4 — Settings and polish.** Real settings, launch at login, theming, export, onboarding,
icon, signed and notarized build.

**M5 — Windows.** Recompile `NotebarCore` under Swift for Windows with a non-GRDB store
implementation, then build a native shell. Scoped by §3 rule 1; the size of this milestone
is the price already accepted for choosing native.

---

## 8. Testing

**Unit (Swift Testing).** `PanelMachine` is a pure reducer, so every flicker scenario is a
table test: cursor exits and returns within `exitDwell`; exit while typing; exit while
dragging; exit with a menu open; pin overriding all of them; screen change mid-expansion.
These are the bugs that are miserable to reproduce by hand and trivial to assert on a pure
function.

`NotebarCore` has no UI imports and so is testable without a host app: repositories
against an in-memory database, link-graph and backlink resolution, fractional reorder
including compaction, shadow-column synchronization.

**E2E (XCUITest).** Only what unit tests cannot reach: the panel expands on edge approach,
collapses on exit, a card drags between columns, a link chip inserts and navigates.

---

## 9. Open item for the author

`PanelMachine.shouldCollapse(...)` encodes how aggressively the panel gets out of the way.
The signals are enumerated in §4.4 and the function is a pure predicate over them, but the
policy is a personal-workflow judgment rather than a technical one, so it is left for the
author to write.

---

## 10. Onboarding — SwiftUI for a React developer

The author's first Swift project. SwiftUI is closer to React than its reputation suggests;
this mapping covers most of what the app uses.

| React / TypeScript | SwiftUI | Note |
|---|---|---|
| `function Card(props) { return <div/> }` | `struct Card: View { var body: some View { ... } }` | A view is a value type, recreated cheaply on every render. |
| `props` | `let` properties on the struct | Immutable by default. |
| `useState` | `@State private var` | Owned by this view. |
| Lifting state up | `@Binding var` | A read/write reference to a parent's state. |
| Context / Zustand store | `@Observable final class` injected with `.environment()` | The app's shared stores. |
| `useEffect(fn, [x])` | `.onChange(of: x) { ... }` | |
| `useEffect(fn, [])` | `.task { ... }` | Also handles async. |
| `{items.map(i => <Row key={i.id}/>)}` | `ForEach(items) { Row(item: $0) }` | `Identifiable` replaces `key`. |
| `{cond && <X/>}` | `if cond { X() }` | Plain control flow in the builder. |
| `className="p-4 rounded"` | `.padding(16).cornerRadius(8)` | Modifiers return a new view; order matters. |
| `<div style={{display:'flex'}}>` | `HStack { }` / `VStack { }` / `ZStack { }` | |
| CSS Grid | `Grid { }` / `LazyVGrid` | |
| `async/await` | `async/await` | Nearly identical syntax. |
| `try/catch` | `do/try/catch` | Errors are typed and must be handled. |
| `T \| undefined` | `T?` | Optionals, with `if let` / `guard let` / `??`. |

**The three genuinely unfamiliar things**, none of which appear outside `Panel/`:

1. **Value vs reference semantics.** `struct` copies, `class` references. Views are
   structs; stores are classes.
2. **`NSViewRepresentable`.** The bridge for wrapping AppKit views (the editor) inside
   SwiftUI.
3. **First responder and window activation.** AppKit's focus model, which the
   non-activating panel depends on.
