# M1 — Rich-text editor and formatting bar

- **Date:** 2026-08-29
- **Status:** Complete

## Summary

Replaced `NoteEditorView`'s plain `TextEditor` with an `NSViewRepresentable`
wrapping `NSTextView`, added the spec §6.2b formatting bar (bold, italic,
inline code, H1, H2, bulleted list, numbered list — checklist deliberately
omitted, out of scope), and markdown input shortcuts (`- `/`* `/`1. `).
Storage moved from `Note.body: String` to `Note.bodyRTF: Data` (RTF) plus
`Note.bodyPlain: String` (the FTS shadow column, now carried on `Note`
itself rather than only in `NoteRow`, since `NotebarCore` can't parse RTF to
derive it — see `Note.swift`'s doc comment).

## Deliverables

1. **Editor** — `Notebar/Features/Notes/NoteEditorView.swift` wraps
   `NSTextView.scrollableTextView()`. Type scale (`Tokens.Typography`): body
   14/20, H1 22/28 semibold, H2 17/22 semibold, code 13/18 monospace. Lists
   use `NSTextList` via `NoteTextStyling.toggleList` — no hand-rolled
   rendering. 400ms debounce and save-on-blur unchanged
   (`PanelViewModel.updateNoteBody`/`flushPendingSave`).
2. **Formatting bar** — `FormattingBarView.swift` (32pt row, 28x28pt hit
   targets, 15pt glyphs, `.secondary`/`.accent`), `NoteTextStyle.swift`
   (the 7 controls + shortcuts), `NoteTextStyling.swift` (toggle + caret-state
   logic shared with markdown shortcuts), `NoteEditingContext.swift` (the
   AppKit↔SwiftUI bridge, fresh per note via `NotesTab`'s
   `NoteEditorContainer`). Shortcuts (`⌘B`/`⌘I`/`⌘⇧C`/`⌘⌥1`/`⌘⌥2`/`⌘⇧8`/`⌘⇧7`)
   are SwiftUI `.keyboardShortcut`s on the buttons, so they fire regardless of
   which view holds first responder. Bar scrolls horizontally
   (`ScrollView(.horizontal)`, fixed height) below the compact breakpoint;
   never wraps. Every button has `.contentShape(Rectangle())`.
3. **Markdown shortcuts** — `NoteMarkdownShortcuts.swift`, hooked from
   `shouldChangeTextIn`; suppresses the triggering space and calls the same
   `NoteTextStyling.toggleList` the bar uses.

## Storage / migration

- New file `Packages/NotebarCore/Sources/NotebarCore/Store/NoteSchema.swift`
  addition: `NoteBodyRTFSchema` (migration name `addNoteBodyRTF`), registered
  in `Migrations.swift` **after** `AppStateSchema`, not next to `NoteSchema`
  — `DatabaseMigrator` rejects a migration inserted before ones a database
  has already applied, and a real upgrade already has
  `OpenTabSchema`/`TaskSchema`/`AppStateSchema` applied.
- Migration adds `body_rtf BLOB`, converts every existing row's `body_plain`
  (identical to the old `body`) into RTF via `NoteRTF.data(from:)`, then
  drops `body`. Verified by
  `NoteBodyRTFMigrationTests.migratesExistingPlainTextBody` — inserts a
  pre-migration row by hand, runs the full migrator, confirms the text
  survives.
- `NoteRTF.swift` (new, in `NotebarStore` — RTF needs AppKit, which
  `NotebarCore` may never import) is the one shared RTF↔`NSAttributedString`
  encoder used by both the migration and the editor.

## Purity guard fix

`scripts/check-core-purity.sh`'s import scan globbed all of
`Packages/NotebarCore/Sources/`, which also covers the `NotebarStore` target.
`NotebarStore` already legitimately depends on GRDB (Apple+Linux only, per
`Package.swift`'s own comment) and now, for the same reason, on AppKit for
RTF — it was never a candidate for the M5 Windows port either guard is
protecting; only `NotebarCore` is. The script's own `Package.swift`-parsing
half already makes this exact target distinction. Scoped both the AppKit ban
and the CoreGraphics/QuartzCore guard to
`Packages/NotebarCore/Sources/NotebarCore/` specifically. Verified the guard
still fails on a probe `import AppKit` placed inside
`Sources/NotebarCore/` (and cleaned the probe up).

## Escape monitor / NSTextView

Read `PanelController.installEscapeMonitor()` (Panel/PanelController.swift):
it already checks `panel.firstResponder is NSText` and passes Escape through
whenever a text view holds first responder. `NSTextView` conforms to `NSText`
directly, so this keeps working unchanged — only updated the comment's
wording (it previously described the old SwiftUI `TextEditor`'s backing
view; now the editor *is* the `NSTextView` directly). No functional change
needed or made.

## Collapse suppression

`NoteEditorView.Coordinator.textDidBeginEditing`/`textDidEndEditing` set
`model.isEditorFocused`; `textDidChange` stamps `model.lastKeystrokeAt = .now`
on every edit (typed, pasted, or a programmatic formatting-bar/markdown edit
followed by an explicit `textView.didChangeText()`). Both still flow through
the unchanged `observeEditorFocused()`/`observeLastKeystroke()` →
`PanelContext` path in `PanelController`.

## isEmptyAndUntitled / all-notes menu

`Note.isEmptyAndUntitled` now checks `bodyPlain` (not `bodyRTF.isEmpty` —
an empty `NSAttributedString` still serializes to a non-trivial RTF header,
so that would never be true). Covered by
`NoteEmptyAndUntitledTests.rtfBodyWithNoVisibleTextIsStillEmpty`. All-notes
menu (`AllNotesMenu.swift`) doesn't touch the body directly and needed no
change.

## Tests

83 tests passing (was 79; +4): RTF round-trip preserving bold
(`GRDBNoteRepositoryRTFTests`), `body_plain` derived from an RTF body
matches its visible text (`bodyPlainMatchesRTFVisibleText`), the migration
converts an existing plain-text body (`NoteBodyRTFMigrationTests`), and
`isEmptyAndUntitled` on an RTF body with no visible characters
(`NoteEmptyAndUntitledTests`).

```
cd Packages/NotebarCore && swift test        # 83 tests, 19 suites, all pass
./scripts/check-core-purity.sh               # OK
xcodebuild ... build                         # BUILD SUCCEEDED
```

## Not run

Per the hard rule, the app itself was never launched — build + `swift test`
+ purity check are the only verification performed. Focus tracking via
`NSTextViewDelegate.textDidBeginEditing`/`textDidEndEditing` is standard,
well-documented AppKit behavior for an always-editable `NSTextView`, but was
verified by reading, not by running the app.

## Out of scope (per instructions)

Checklists (`⌘⇧9`, `checklist` glyph) — need a clickable `NSTextAttachment`,
explicitly deferred to a separate task. No checklist button exists in the
bar.
