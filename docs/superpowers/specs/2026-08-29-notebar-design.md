# Notebar — Design Spec

- **Date:** 2026-08-29
- **Status:** Draft, pending approval
- **Stack:** Electron + React + TypeScript
- **Platform:** macOS first, Windows via a platform adapter

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

1. Cursor reaches the edge, panel fully expanded, in under 250 ms.
2. Capturing a note from any app requires no click on any window but Notebar's.
3. The panel never collapses while the user is mid-thought — typing, dragging, or with a
   menu open.
4. Idle cost under 1% CPU.
5. No permission prompt on first launch, on either platform.

### Non-goals for v1

Cloud sync, multi-device, sharing, collaboration, mobile, plugins, AI features, calendar
integration, reminders. The schema is designed not to preclude sync; nothing is built
for it.

---

## 2. Stack decision

The user is fluent in TypeScript and Node, has no Rust or Swift toolchain installed, and
stated they do not know SwiftUI or macOS native development. The stack question therefore
resolves on a single criterion: **where does the hard code live, and can the author debug
it?**

Every candidate must implement the same four difficult behaviours — an always-on-top
window that floats over fullscreen apps, permission-free global cursor polling, a tray
presence with no Dock icon, and launch-at-login. What differs is the language those
behaviours are written in.

| Candidate | Hard parts written in | Windows path | Verdict |
|---|---|---|---|
| SwiftUI + AppKit | Swift + AppKit | Full second app, ~0% reuse | Rejected — author cannot debug the riskiest code |
| Tauri v2 | **Rust** (+ a third-party plugin for macOS panel semantics) | Good | Rejected — no Rust toolchain; a second unknown language stacked on native semantics |
| **Electron** | **TypeScript** (all first-party APIs) | One platform-adapter module | **Selected** |

Electron's cost is memory: roughly 200 MB resident versus roughly 60 MB for a native
build. For an always-running personal utility on an Apple Silicon machine, that is an
acceptable price for keeping every line of the application in one language the author
writes daily — and it removes the Windows rewrite entirely.

### Toolchain

| Concern | Choice | Why |
|---|---|---|
| Shell | Electron (latest stable) | First-party APIs for every window behaviour required. |
| Build | electron-vite | Fast HMR in the renderer; sane main/preload/renderer split. |
| Package | electron-builder | DMG and NSIS, code signing, notarization, auto-update later. |
| UI | React 19 + TypeScript (strict) | Author's daily stack. |
| Editor | TipTap (ProseMirror) | Mature WYSIWYG; custom nodes make link chips a first-class concept rather than a hack. |
| Drag & drop | dnd-kit | Actively maintained, accessible, handles both board layouts with one sensor set. |
| Database | SQLite via better-sqlite3 | Synchronous API, no async ceremony in the main process. |
| Query layer | Drizzle ORM | Type-safe schema and migrations; types flow from schema to UI. |
| Styling | Tailwind CSS + CSS variables | Variables carry the theme so light/dark and the material layer are one source of truth. |
| Tests | Vitest, plus Playwright for Electron | State machine and repositories unit-tested; a thin E2E layer over the real window. |

### Decisions made on the user's behalf

Each is reversible and flagged for review.

1. **Board columns are data, not an enum.** Seeded with Queue / Working / Done, stored as
   rows, so user-defined statuses in v2 need no migration.
2. **Note content persists as ProseMirror JSON plus a plain-text shadow column.** JSON is
   lossless for custom link-chip nodes; the shadow column feeds full-text search. HTML and
   Markdown export are features, not the storage format.
3. **Open note tabs persist across restarts.** Matches the Notepad++ mental model the user
   referenced — the session is part of the state.
4. **The Tasks board adapts to panel width** — stacked status groups when narrow,
   side-by-side kanban when wide. See §6.3.

---

## 3. Architecture

```
Notebar/
├── electron.vite.config.ts
├── electron-builder.yml
└── src/
    ├── main/                       Node context · owns windows, cursor, database
    │   ├── index.ts                app lifecycle, single-instance lock
    │   ├── panel/
    │   │   ├── PanelWindow.ts      BrowserWindow creation + platform flags
    │   │   ├── HotEdgeMonitor.ts   adaptive cursor polling
    │   │   ├── panelMachine.ts     PURE reducer — no Electron imports
    │   │   └── PanelController.ts  wires monitor + machine + window
    │   ├── platform/
    │   │   ├── index.ts            PlatformAdapter interface
    │   │   ├── darwin.ts           macOS specifics
    │   │   └── win32.ts            Windows specifics
    │   ├── db/                     schema.ts, migrations/, repositories/
    │   ├── ipc/                    typed channel handlers
    │   └── tray.ts, shortcuts.ts, autoLaunch.ts
    ├── preload/
    │   └── index.ts                contextBridge — the ONLY main/renderer surface
    ├── renderer/                   React · no Node access
    │   ├── App.tsx                 tab rail + active tab
    │   ├── features/               notes/ · tasks/ · settings/
    │   ├── linking/                MentionExtension, LinkChipNode, Backlinks
    │   ├── design-system/
    │   └── lib/                    api.ts (typed wrapper over preload), queries
    └── shared/                     types + Zod schemas used by BOTH sides
```

### Three rules that carry the architecture

**1. `src/shared/` is the contract.** Every IPC payload is a type and a Zod schema
declared once in `shared/` and imported by both sides. The renderer cannot drift from
the main process because they compile against the same definitions.

**2. `panelMachine.ts` imports nothing from Electron.** The panel's behaviour — the part
most likely to produce subtle, hard-to-reproduce bugs — is a pure function:

```ts
(state: PanelState, event: PanelEvent, ctx: PanelContext) => [PanelState, Effect[]]
```

Every flicker scenario becomes an ordinary table-driven unit test instead of something
reproduced by waving a mouse at the screen. `PanelController` is the only code that
translates `Effect[]` into real window calls.

**3. Platform differences live in exactly one directory.** `src/main/platform/`
implements one interface:

```ts
interface PlatformAdapter {
  configurePanelWindow(win: BrowserWindow): void
  hideFromTaskSwitcher(): void
  setLaunchAtLogin(enabled: boolean): void
  readonly supportsFullscreenOverlay: boolean
}
```

Shipping Windows means writing `win32.ts`. Nothing else in the codebase is
platform-aware. This is the whole Windows strategy, and it is enforceable by review.

### Security posture

`contextIsolation: true`, `nodeIntegration: false`, `sandbox: true`. The renderer reaches
the main process only through the preload bridge, and every payload crossing it is
validated with its Zod schema on arrival. The renderer never touches SQLite directly.

---

## 4. The panel

### 4.1 Window configuration

A single `BrowserWindow`, created once at launch and hidden rather than destroyed, so
expansion never pays window-creation cost.

```ts
new BrowserWindow({
  width: 420, height: screenHeight,
  frame: false, transparent: true, resizable: true,
  skipTaskbar: true, show: false,
  type: process.platform === 'darwin' ? 'panel' : undefined,
  webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true },
})
```

Then, in the platform adapter:

| Call | Effect |
|---|---|
| `win.setAlwaysOnTop(true, 'screen-saver')` | Above normal windows and most system UI. |
| `win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })` | Appears over fullscreen apps and follows the user across Spaces. macOS-specific; a no-op on Windows. |
| `win.showInactive()` | Reveals the panel without stealing focus from the frontmost app. Focus is taken only when the user clicks or types into it. |
| `app.dock.hide()` | No Dock icon. Paired with `LSUIElement` in the packaged Info.plist. |

`type: 'panel'` gives the window NSPanel semantics on macOS, which is what allows it to
accept keystrokes without activating the whole application.

### 4.2 Hot edge detection

```
setInterval → screen.getCursorScreenPoint()
                ├── idle       10 Hz    cursor far from any edge
                └── near edge  60 Hz    cursor within 80 px of the active display's right edge
```

`screen.getCursorScreenPoint()` needs **no Accessibility permission on macOS and no
permission on Windows**, and returns the same shape on both. This is why the fully
invisible activation the user asked for is viable with no first-run prompt — and why the
detection code itself is genuinely cross-platform.

The active display is resolved with `screen.getDisplayNearestPoint(cursor)`, so
multi-monitor works by construction. Only that display's right edge triggers in v1; edge
and display selection become settings later.

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

**Timings** — all surfaced in Settings later:

| Constant | Default | Meaning |
|---|---|---|
| `edgeDwell` | 120 ms | Cursor must rest in the trigger zone this long before expanding. Prevents accidental opens when reaching for a scrollbar. |
| `triggerWidth` | 2 px | Width of the trigger zone at the display edge. |
| `exitSlop` | 24 px | Cursor must clear the panel bounds by this margin before the exit timer starts. |
| `exitDwell` | 350 ms | Cursor must remain outside this long before collapsing. |
| `expandDuration` | 180 ms | Slide-in. |
| `collapseDuration` | 140 ms | Slightly faster out than in — reads as responsive rather than sluggish. |

### 4.4 Collapse suppression

This is the difference between a panel that feels alive and one that feels hostile. The
naive implementation collapses on pointer-leave and is unusable in practice: the panel
vanishes when the user reaches for a menu, drags a card, or glances away mid-sentence.

Collapse is suppressed while **any** of these hold:

| Signal | Source |
|---|---|
| `isPinned` | User toggled pin, or summoned via hotkey |
| `hasOpenOverlay` | A menu, popover, dropdown, or modal is open |
| `isDragging` | A dnd-kit drag is in flight |
| `isEditorFocused` | A TipTap editor holds focus |
| `msSinceLastKeystroke` | Renderer reports typing activity |
| `isWindowFocused` | The panel window is focused |

The exact policy is a workflow judgment rather than a technical one, and is left for the
author to write — see §9.

---

## 5. Data model

SQLite via Drizzle. Schema shown as SQL for clarity; the source of truth is
`src/main/db/schema.ts`.

```sql
CREATE TABLE note (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL DEFAULT '',
  body_json    TEXT,                      -- ProseMirror document
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
  detail_json  TEXT,
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
that references this" into a union across N tables. Retrofitting this later is the
single most expensive change in the design, which is why it is here on day one.

### Why `sort_order REAL`

Fractional ordering. Dropping a card between two others assigns the midpoint of their
orders, so a reorder is one row update instead of renumbering the column. A compaction
pass renormalizes when gaps approach float precision.

### Why JSON plus a plain shadow column

`body_json` is TipTap's native format and is lossless for custom link-chip nodes.
`body_plain` is derived on every save and is what FTS5 indexes, so search never parses a
document. The pair gives WYSIWYG fidelity and fast search without compromise.

---

## 6. Feature design

### 6.1 Application tab rail (left)

A ~56 px vertical rail: Notes, Tasks, Settings. Icon with label beneath at default width;
icon-only below 340 px. The selected tab persists in `app_state` and is what the panel
shows on its next expand, so the panel resumes where the user left it.

### 6.2 Notes

A horizontal tab strip across the top of the content area, Notepad++ style: click to
switch, drag to reorder, middle-click or `Cmd/Ctrl+W` to close, `Cmd/Ctrl+T` for a new
note. The strip scrolls horizontally with an overflow chevron listing hidden tabs —
necessary because at 420 px only three or four tabs fit.

The editor is TipTap with a compact toolbar: bold, italic, code, bullet and ordered
lists, checkboxes, headings. Open tabs are rows in `open_tab`, so the session survives a
restart. `Cmd/Ctrl+P` opens quick search across `note_fts` and `task_fts`.

Saves are debounced at 400 ms and on blur; `body_plain` is regenerated from the document
in the same transaction that writes `body_json`, so the search index can never drift.

### 6.3 Tasks

A Jira board in a narrow panel needs a layout that adapts to width:

```
  panel < 700 px                       panel ≥ 700 px
  ┌────────────────────────┐           ┌──────────────────────────────────────┐
  │ ▼ Queue           (4)  │           │  Queue      Working       Done       │
  │   ┌──────────────────┐ │           │ ┌────────┐ ┌────────┐  ┌────────┐    │
  │   │ Fix edge flicker │ │           │ │ Fix    │ │ Panel  │  │ Schema │    │
  │   ├──────────────────┤ │           │ │ edge   │ │ anim   │  │ draft  │    │
  │   │ Schema review    │ │           │ ├────────┤ ├────────┤  ├────────┤    │
  │   └──────────────────┘ │           │ │ Schema │ │ Tab    │  │ Spike  │    │
  │ ▼ Working         (2)  │           │ │ review │ │ strip  │  │ JSON   │    │
  │   ┌──────────────────┐ │           │ └────────┘ └────────┘  └────────┘    │
  │   │ Panel animation  │ │           │                                      │
  │   └──────────────────┘ │           │                                      │
  │ ▶ Done            (7)  │           │                                      │
  └────────────────────────┘           └──────────────────────────────────────┘
   collapsible status groups            true side-by-side kanban
   drag between groups                  drag between columns
```

Both layouts share one dnd-kit context, one droppable-per-column model, and one reorder
mutation — only the arrangement differs. Dropping a card writes `column_id` and a
fractional `sort_order`; a drop into a `done`-kind column stamps `completed_at`, and
dragging back out clears it.

A drag in flight suppresses collapse for its whole duration (§4.4). A drag released
outside the panel is cancelled, not dropped.

### 6.4 Linking

- Typing `@` in a note or task detail opens an autocomplete over notes and tasks, ranked
  by recency then FTS relevance. Selecting one inserts a **link chip** — a custom TipTap
  node holding the target's type and id — and writes a `link` row in the same transaction.
- Dragging a task card onto an open note inserts a chip at the drop point.
- Every note and task shows a **Backlinks** section listing inbound references: one query
  on `idx_link_dst`.
- Clicking a chip opens the target — notes as a new tab, tasks as a detail sheet.
- Deleting an entity soft-deletes it; existing chips render as tombstones rather than
  silently deleting text the user wrote.

### 6.5 Settings

Shell only in v1. The tab renders placeholder sections that the design already implies —
Activation (edge, dwell timings, hotkey), Appearance (width, theme), Data (database
location, export), General (launch at login) — so filling them in later is wiring, not
design.

---

## 7. Milestones

Each milestone ends in a commit and push, per the workspace checkpoint rule.

**M0 — Shell.** electron-vite scaffold, panel window with platform flags, hot edge
monitor, state machine with suppression, tab rail, three empty tabs, tray, global
hotkey. Deliberately first: if the panel does not feel right, nothing downstream matters.

**M1 — Notes.** Drizzle schema and migrations, repositories, typed IPC, TipTap editor,
tab strip, open-tab persistence, FTS search, quick open.

**M2 — Tasks.** Board and column seeding, task CRUD, both layouts, dnd-kit wiring,
fractional reordering with compaction, completion stamping.

**M3 — Linking.** `@` autocomplete, link chip node, `link` writes, backlinks, drag-to-link,
tombstones.

**M4 — Settings and polish.** Real settings, launch at login, theming, export, onboarding,
icon, signed and notarized build.

**M5 — Windows.** Implement `platform/win32.ts`, verify overlay and cursor behaviour, NSIS
installer. Scoped as one module because §3 rule 3 kept it that way.

---

## 8. Testing

**Unit (Vitest).** `panelMachine` is a pure reducer, so every flicker scenario is a table
test: cursor exits and returns within `exitDwell`; exit while typing; exit while dragging;
exit with a menu open; pin overriding all of them; display change mid-expansion. These are
the bugs that are miserable to reproduce by hand and trivial to assert on a pure function.

Repositories run against an in-memory SQLite database, covering link-graph and backlink
resolution, fractional reorder including compaction, and shadow-column synchronization.

**E2E (Playwright for Electron).** Only what unit tests cannot reach: window expands on
edge approach, collapses on exit, a card drags between columns, a link chip inserts and
navigates.

---

## 9. Open item for the author

`shouldCollapse()` in `src/main/panel/panelMachine.ts` encodes how aggressively the panel
gets out of the way. The signals are enumerated in §4.4 and the function is a pure
predicate over them, but the policy is a personal-workflow judgment rather than a
technical one, so it is left for the author to write.
