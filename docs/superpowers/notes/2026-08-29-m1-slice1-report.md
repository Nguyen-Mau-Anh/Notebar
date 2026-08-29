# M1 slice 1 report — pin, tab toolbar, working Notes/Tasks

STATUS: DONE

Commit: `02c753b` (pushed to `origin/main`)

Build: `BUILD SUCCEEDED`. Tests: `29/29` passed. `core purity: OK`.

## Deliverables

1. **Pin toggle** — `PanelViewModel.isPinned` added; `TabRail`'s new `PinToggle` (56pt-wide,
   `Tokens.Size.pinHeight`=32) binds to it above a `Divider()`; `PanelController.observePin()`
   uses `withObservationTracking` (re-armed on each fire) to mirror `model.isPinned` into its
   existing `isPinned` proxy onto `PanelContext`. `PanelMachine`/`PanelContext` untouched.
2. **Tab toolbar** — new shared `TabToolbar`/`ToolbarActionButton` (36pt row, 1px hairline,
   28x28pt action button) used by all three tabs per the left/right table.
3. **Notes** — horizontal `NoteTabStrip` (click to switch, tail-truncated, id-keyed close),
   `+` creates and activates an untitled note, body is `TextEditor` behind `NoteEditorView`
   (the documented future-`NSTextView` seam), title derives live from the first non-empty
   line. Closing the last note shows the existing `PlaceholderTab` empty state.
4. **Tasks** — `+` appends `"New task"` to the seeded first group (`Queue`); toolbar shows
   `Tasks` + total count; groups stay `Queue`/`Working`/`Done`, no dragging.

State lives directly on `PanelViewModel` (no separate `NotesStore`) — `selection` already
lived there for the same reason (collapsed handle needs it), so notes/tasks state joined it.

Traps: did not hit trap 1 (`shouldCollapse` ignoring `isEditorFocused`) or trap 2 (Escape
monitor) while building — no runtime exercise was done (see below), so this is not a
runtime observation, only that nothing in the code paths touched forced a decision on either.
Both remain exactly as flagged in the risks doc and are now reachable at runtime with a real
`TextEditor` in place.

⚠️ Visual/interaction behavior (pin persisting, toolbar hover states, typing focus vs. edge
collapse, Escape-in-editor) cannot be verified — requires the user's live desktop, which was
not touched per the hard rule.

`build/` holds the rebuilt binary (`Notebar.app`, built at this session's `xcodebuild` run);
`git status --porcelain` is empty.
