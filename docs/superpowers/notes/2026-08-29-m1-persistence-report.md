# M1 persistence — notes survive a quit

Implements spec §5 for notes only (tasks/links/tags deferred), behind the `NotebarCore` /
`NotebarStore` split spec §3 rule 1 requires, per the M1 risk item on the purity guard.

## Deliverable 1 — purity guard now reads Package.swift

`scripts/check-core-purity.sh` parses `Packages/NotebarCore/Package.swift` with an
embedded Python step: it locates the `.target(name: "NotebarCore", ...)` block (paren-depth
tracked, so nested calls like `swiftSettings` don't confuse the boundary) and fails if it
declares any `dependencies:` entries. The `NotebarCoreTests` test target depending on
`NotebarCore` is unaffected — only the library target itself is checked.

**Proof it catches the mistake** — added `dependencies: ["DummyNonPortableDependency"]` to
the `NotebarCore` target, ran the guard:

```
ERROR: the NotebarCore target in Package.swift declares a dependency:

.target(
            name: "NotebarCore",
            dependencies: ["DummyNonPortableDependency"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )

NotebarCore must have ZERO dependencies (spec section 3, rule 1). It exists so a Windows
port (M5) can recompile it as-is; any dependency — even one that only targets Apple
platforms and Linux, like GRDB — would need to resolve and build on Windows too, which
breaks that plan even though this guard's source-import checks above would still print
"core purity: OK".
Put the dependency on NotebarStore (or another new target) instead, behind the repository
protocols NotebarCore already defines. The NotebarCoreTests test target may depend on
NotebarCore itself — that's a different rule and is fine.
EXIT=1
```

Reverted, ran again:

```
Package.swift dependency check: OK
core purity: OK
EXIT=0
```

Both existing checks (AppKit/SwiftUI/UIKit/Cocoa forbidden outright; CoreGraphics/QuartzCore
only behind `#if canImport`) are untouched and still run first.

## Deliverable 2 — schema + protocols in NotebarCore

- `Note` (`Models/Note.swift`): `id`, `title`, `body`, `createdAt`, `updatedAt`,
  `sortOrder: Double`, `isPinned`. `body` is plain `String` for this milestone (rich text is
  a later task); `derivedTitle` reproduces the M0 in-memory model's exact "first non-empty
  line, else Untitled" logic as a pure computed property, so the UI's live-title behavior is
  bit-for-bit unchanged even though `title` is now a real stored column.
- `NoteRepository` protocol: `all()`, `create()`, `update(_:)`, `delete(id:)`,
  `reorder(id:before:after:)`, `search(_:)`. **Synchronous, throwing** — GRDB's
  `DatabaseQueue` is itself a synchronous, serializing API, so `async` would only add
  Task/actor overhead for sub-millisecond local writes, and would fight the package's
  deliberate Swift 5 language mode (spec §2, kept for the author's unfamiliarity with
  Swift's newer concurrency diagnostics). Callers that must not block their own thread
  (`PanelViewModel`'s debounced saves) dispatch to a background queue themselves.
- `NoteSchema` (`Store/NoteSchema.swift`): the `note` table, the `note_fts` FTS5 virtual
  table, and the three sync triggers, as string constants — `NotebarStore` writes no SQL
  this module doesn't declare. One documented deviation from spec §5's literal SQL: the
  column holding content is named `body` (plain text now) rather than `body_rtf` (a BLOB),
  since rich text is out of scope here; `body_plain` is present as a real shadow column
  exactly as spec asks, so only how it's *derived* changes when rich text lands, not the
  shape FTS depends on.
- `OpenTab` + `OpenTabRepository` + `OpenTabSchema` (`open_tab` table): added to support
  deliverable 4's tab persistence — see below.

## Deliverable 3 — NotebarStore

New target in the same `Package.swift`, depending on `NotebarCore` + GRDB
(`https://github.com/groue/GRDB.swift`, `from: "7.0.0"`, resolved to 7.11.1,
`Package.resolved` committed for reproducible CI resolution).

- `GRDBNoteRepository` / `GRDBOpenTabRepository`, each backed by a private `NoteRow` /
  `OpenTabRow` (`Codable, FetchableRecord, PersistableRecord`) — the bridge type that lets
  GRDB conformances exist without `Note`/`OpenTab` (or `NotebarCore`) ever importing GRDB.
- `Migrations.migrator`: one `DatabaseMigrator` with two named migrations,
  `NoteSchema.migrationName` (creates `note` + `note_fts` + the sync triggers) and
  `OpenTabSchema.migrationName` (creates `open_tab`).
- `NotebarDatabase.openDefault()` opens (creating if needed)
  `~/Library/Application Support/Notebar/notebar.sqlite`; `openInMemory()` is the same
  migration path against an in-memory `DatabaseQueue`, used by tests, previews, and as a
  fallback if the on-disk open fails.
- `body_plain` same-transaction guarantee: `NoteRow.init(_ note:)` is the *only* place that
  derives `bodyPlain`, always from `body`, and every write path (`create`, `update`) goes
  through it before a single `INSERT`/`UPDATE` — so there's no code path that can write one
  without the other. FTS5 sync then rides the same statement via the triggers, which fire in
  the same transaction as that statement.

## Deliverable 4 — wired into the UI, open tabs persist

`PanelViewModel` takes `noteRepository`/`openTabRepository` in its designated init;
`AppDelegate` builds the real GRDB-backed pair via `NotebarDatabase.openDefault()` (falling
back to `openInMemory()` — logged, not surfaced as a dialog — if Application Support can't be
opened, so spec §1's "no permission prompt" criterion holds even in that failure case). The
no-arg `convenience init()` used by SwiftUI previews opens an in-memory store instead.

- `NotesTab`/`NoteEditorView` are otherwise unchanged in shape: the `+` button, tab strip,
  and editor still bind to `model.notes`/`model.activeNoteID` the same way. `note.title` in
  the tab strip became `note.derivedTitle` (same computation, now on the persisted type);
  the body binding's setter now calls `model.updateNoteBody(id:body:)` instead of mutating
  the array directly, and tab selection goes through `model.selectNote(id:)` instead of a
  raw property set, since both now also need to touch persistence.
- **Debounce**: `PanelViewModel.noteSaveDebounceInterval = 0.4` (named constant, no magic
  number). Every keystroke updates the in-memory `notes` array immediately (UI never lags)
  and (re)schedules a `DispatchWorkItem` 400ms out; `flushPendingSave(id:)` cancels and saves
  immediately on editor blur (`NoteEditorView`'s `onChange(of: isFocused)`) and on tab
  switch/close; `flushAllPendingSaves()` runs from `AppDelegate.applicationWillTerminate` so
  quitting within the debounce window never drops a keystroke. All repository writes happen
  on a dedicated background `DispatchQueue` (`.utility`), never the main thread.
- **Open tabs: implemented.** It was cheap — `persistOpenTabs()` replaces the whole
  `open_tab` set on structural changes only (create/close/select, never per keystroke), and
  `loadPersistedState()` rebuilds `notes`/`activeNoteID` from it at launch, joined against
  `noteRepository.all()`. One deliberate scope note: closing a tab removes it from the open
  set but does not delete the note row, so a closed note becomes inaccessible until a notes
  browser exists (no such UI ships in this milestone) — flagged rather than silently
  decided.
- App target (`project.yml`) gains a `NotebarStore` product dependency alongside the
  existing `NotebarCore` one.

## Deliverable 5 — tests

`NotebarStoreTests` (new test target, in-memory `DatabaseQueue` per test): create/read,
update, delete, delete-of-unknown-id, update-of-unknown-id throws, `updatedAt` advances;
`body_plain` matches `body` after create and after update; FTS finds a note by a body word
and excludes a deleted one, blank query returns empty; fractional `sortOrder` — insert
between two notes, insert at start, insert at end.

## Build/test evidence

```
$ cd Packages/NotebarCore && swift test
Test run with 53 tests in 9 suites passed  (36 pre-existing + 17 new, all green)

$ ./scripts/check-core-purity.sh
Package.swift dependency check: OK
core purity: OK

$ xcodebuild ... build
** BUILD SUCCEEDED **
```

`build/Build/Products/Debug/Notebar.app/Contents/MacOS/Notebar` was rebuilt by this run
(timestamp confirmed newer than the source edits) — the app was never launched or driven.

## Constraints confirmed

- `NotebarCore`'s `Package.swift` target declares **zero dependencies** — verified by the
  guard above, not just by inspection.
- `NotebarCore` still imports no AppKit/SwiftUI/UIKit; `PanelMachine`/`PanelContext`/geometry
  untouched.
- `NotebarStore` targets macOS 14, same as `NotebarCore`; the app target stays macOS 26.
- No magic numbers: the debounce interval is `PanelViewModel.noteSaveDebounceInterval`.
