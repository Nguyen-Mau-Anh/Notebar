# What a Windows port actually requires

Written at the end of M1, from the code as it stands. `NotebarCore` was kept portable from
day one and that discipline held — but the honest accounting is narrower than the intent,
and one decision made during M1 has to be undone before a port is possible at all.

## The measurement

| Target | Lines | Windows |
|---|---|---|
| `NotebarCore` | 1,426 | Recompiles as-is. Swift officially supports Windows. |
| `NotebarStore` | 1,633 | Replace. GRDB, AppKit, `os`, CoreGraphics. |
| `Notebar` (app) | 5,183 | Rewrite. SwiftUI and AppKit do not exist on Windows. |
| Tests | 2,017 | Come free — they exercise `NotebarCore`. |

**17% of non-test code ports unchanged.** That is the real number. It is worth having: it
contains `PanelMachine`, `EdgeZone`, `NoteListMarkers`, `PanelTiming`, the models, and the
repository protocols — the parts that were hard to get right, and that 153 tests already
pin. The UI is the larger half but the easier one.

## The blocker is the storage format, not the database

GRDB targets Apple platforms and Linux, not Windows. That is the constraint the purity
guard was built around, and it is **the easy problem**: swap it for another SQLite binding
behind the existing `NoteRepository` / `TaskRepository` / `LinkRepository` protocols. Those
protocols exist precisely so this is a substitution rather than a rewrite.

**RTFD is the hard problem, and it is not solvable by substitution.**

Note bodies are stored as flat RTFD — a serialization of `NSAttributedString`. That type is
AppKit. It has no counterpart on Windows, and no third-party reader worth trusting. Every
note written since the rich-text milestone is in a format a Windows build **cannot read at
all**, and the same applies to:

- **link chips**, which are `.link` attributes inside the RTFD
- **checklist markers and list markers**, which are text plus `NSTextList` paragraph styles
- **inline images**, which are `NSTextAttachment`s inside the RTFD

This was the right call for a macOS-only app — it made rich text, images, chips, and lists
nearly free. It is the single decision standing between here and a port.

**It gets more expensive every day the app is used**, because every new note is another row
in a format that has to be converted.

## What to do, in order

### 1. Move the body to a portable format (do this first)

Replace RTFD as the *source of truth* with something both platforms can read. Options, best
first:

- **HTML** — round-trips through `NSAttributedString` on macOS with no new dependency,
  carries bold/italic/headings/lists natively, and `<a href="notebar://…">` is exactly what
  the link chips already are. Images become `<img>` with a reference rather than embedded
  bytes.
- **A structured JSON document** (ProseMirror-shaped) — lossless and explicit, but you write
  the macOS renderer yourself.
- **Markdown plus extensions** — most portable and most human-readable, but lossy for
  anything it does not model.

HTML is the recommendation: it is the only one where the macOS side stays nearly free.

Do it as an additive migration that converts existing RTFD, exactly like the six before it.

### 2. Move images out of the body

Currently embedded as attachment bytes inside the RTFD blob. Move them to an `attachment`
table or files on disk, referenced by id. This is worth doing **regardless of Windows** —
it is why `summaries()` had to exist, and it keeps note rows small.

### 3. Swap the database binding

Behind the existing repository protocols. Mechanical once (1) and (2) are done, because the
protocols no longer traffic in Apple-only types.

### 4. Decide the UI story

There is no good Swift UI framework on Windows. Realistic options:

- **WinUI 3 in C#**, calling into the Swift core over a C ABI. Best-looking result, most
  interop work.
- **Rewrite the UI in C# entirely** and treat `NotebarCore` as a specification rather than
  shared code — port the state machine's 153 tests as the acceptance criteria.
- **A cross-platform toolkit.** Cheapest, and gives up the native feel that motivated
  choosing SwiftUI in the first place.

Note what the app actually needs from the platform: an always-on-top borderless window that
survives virtual-desktop switches, permission-free global cursor polling, a system-wide
hotkey, and a tray icon. All four exist on Windows and none are exotic — the panel concept
ports cleanly even though none of its code does.

## The honest recommendation

**Do step 1 now, and only step 1.** Converting the body format is cheap today, gets more
expensive with every note written, and is worth doing on its own merits — a portable,
greppable, inspectable body format is better than an opaque Apple blob even if Windows never
happens.

Steps 2 through 4 should wait until there is a reason beyond "it would be nice." A Windows
port is roughly a rewrite of 6,800 lines with 1,400 reused. That is a real project, not a
milestone, and it should be started because someone wants to run it on Windows — not because
the architecture was arranged to allow it.

The architecture being arranged to allow it is what makes it a decision you can still make.
That was the point.
