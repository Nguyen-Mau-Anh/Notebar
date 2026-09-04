# Notebar

A macOS scratch surface that lives at the right edge of your screen. Collapsed it is a
small handle; hover it and a panel slides out over whatever you are working in — including
fullscreen apps — then retreats when you are done with it.

It holds notes and tasks, and it is built so that it never interrupts you: the panel
refuses to collapse while you are typing, dragging a card, or have a menu open.

**It has never shown a permission prompt, and by construction it cannot.**

### [⬇ Download v0.1.0](https://github.com/Nguyen-Mau-Anh/Notebar/releases/latest)

Requires macOS 26+. Open the `.dmg`, drag Notebar to Applications. **The first launch is
blocked** — allow it under **System Settings → Privacy & Security → Open Anyway**. That is
once per install, not per launch; the build is ad-hoc signed but not notarized. On macOS 15
and later, Control-click → Open no longer bypasses this.

<!-- Add a screenshot here: the handle at the edge, and the panel expanded. -->

## What it does

**Panel** — invisible except for a 30×56pt handle at the right edge. Hover it to expand to
340pt wide × 70% of screen height, vertically centred. Pin it open, maximize it to half the
screen, dismiss it with the `»` button, or toggle it from anywhere with `⌘⇧Space`. A menu
bar icon quits it. No Dock icon.

**Notes** — multiple notes as tabs, Notepad++ style. Rich text with bold, italic, inline
code, two heading levels, and bulleted and numbered lists with working markers. Paste
images inline. Rename by double-click, delete from the right-click menu, find any note from
the all-notes menu, search full-text.

**Tasks** — a board with Queue / Working / Done. Click a card to expand an editable detail
in place; drag cards between groups to change status, which stamps and clears completion
times automatically.

**Settings** — Light, Dark, or follow the system, switching live. Database location, size,
and a diagnostics export for bug reports.

Everything persists to SQLite. Open tabs come back where you left them.

## Requirements

- macOS 26 or later
- Xcode 26 (the app targets the macOS 26 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build and run

```sh
make build     # generate the Xcode project and build
make run       # build, then launch
make test      # the NotebarCore test suite
make check     # the core-purity guard
```

`Notebar.xcodeproj` is **generated** from `project.yml` and is gitignored. Never edit it by
hand — change `project.yml` and run `make gen`.

`make dmg` builds a Release `.app` and wraps it in a drag-to-Applications `.dmg` under
`build-release/`. That is how the [release](https://github.com/Nguyen-Mau-Anh/Notebar/releases/latest)
is produced.

## Architecture

Three layers, split along one line: **what could run on Windows, and what could not.**

```
Notebar (app target)          AppKit + SwiftUI. The panel window, the cursor
      │                       monitor, every view. macOS 26+.
      ▼
NotebarStore                  GRDB, RTFD, image handling. Apple-only, and
      │                       deliberately so.
      ▼
NotebarCore                   Pure Swift. Models, repository protocols, the
                              panel state machine. macOS 14+, ZERO dependencies.
```

`NotebarCore` may not import AppKit, SwiftUI, UIKit, Cocoa, `os`, OSLog, Combine, CoreData,
SwiftData, or CryptoKit, and may not declare **any** package dependency. None of those have
a Linux or Windows counterpart, so any of them would end the possibility of a Windows port
that reuses this code.

That rule is enforced mechanically by `scripts/check-core-purity.sh`, which runs in CI and
in `make check`. It has caught two real regressions that compiled fine and passed every
test.

**The panel's behaviour is a pure function.** `PanelMachine.reduce(state, event, context)`
returns a new state and a list of effects, with no clocks, no I/O, and no AppKit. Time
arrives as events; `PanelController` is the only code that turns an effect into a window
call. That is why flicker bugs — the kind that are miserable to reproduce by waving a mouse
at the screen — are ordinary table-driven unit tests here.

## Documentation

| | |
|---|---|
| [Product and architecture spec](docs/superpowers/specs/2026-08-29-notebar-design.md) | The binding design document. Panel behaviour, data model, every feature. |
| [Screen design spec](docs/design/2026-08-29-screen-spec.md) | Tokens, type scale, states, both appearances. |
| [M0 implementation plan](docs/superpowers/plans/2026-08-29-notebar-m0-shell.md) | How the shell was built, task by task. |
| [M1 risks](docs/superpowers/notes/2026-08-29-m1-risks.md) | Known debt carried forward. |

There is also a [Figma file](https://www.figma.com/design/m7at12IVVHYIl5AOU4Bxrh) with the
token system and screen designs.

## Status

The panel, notes, tasks, settings, persistence, and diagnostics all work. 122 tests.

**Not built yet:**

- **Checkboxes** in the editor — deferred; they need clickable text attachments.
- **Note ↔ task linking** — the storage and `@`-mention half is in progress; backlinks,
  drag-to-link, and tombstones follow.
- **Activation settings** — the dwell timings and exit slop are constants, not yet sliders.
- **Windows** — a first release now exists (see [Windows](#windows) above); its own manual
  verification is still catching up, since it was built entirely from a Mac that cannot run
  WinUI 3 at all.
- **No app-target tests.** All 122 live in `NotebarCore`. `PanelViewModel` and the views
  have none, which is exactly where the interaction bugs have been found by hand.

## Distribution

`make dmg` produces an installable `.dmg`, and releases are published from it.

The build is **ad-hoc signed but not notarized**, which means a Mac other than the one that
built it blocks the first launch — they can allow it under **System Settings →
Privacy & Security → Open Anyway**, which works but is alarming. Removing that warning
requires notarization, which requires a Developer ID certificate, which requires the
$99/year Apple Developer Program.

Note that on macOS 15 and later, Control-click → Open no longer bypasses this. System
Settings is the only route.

## Windows

An early WinUI 3 / C# port lives in `windows/`: the same panel, notes, tasks, and settings
as the macOS app, built from scratch against the same design rather than sharing code with
it. **The two platforms keep entirely separate databases and do not sync** — a note written
on macOS is not visible on Windows, and vice versa.

### [⬇ Download the Windows build](https://github.com/Nguyen-Mau-Anh/Notebar/releases?q=windows-v)

Unzip `Notebar-portable-x64.zip` and run `Notebar.App.exe`. The build is unsigned, so
Windows SmartScreen warns on first run — click **More info**, then **Run anyway**. See
[`docs/release-notes-windows.md`](docs/release-notes-windows.md) for the full explanation,
an MSIX install alternative if one is attached to the release, and what has not yet been
verified on a real Windows machine.

Built and tested against Windows 11, version 22H2 or later, x64 — it also runs on arm64
Windows under emulation, but there is no native arm64 build yet. Needs the Microsoft Edge
WebView2 Runtime, preinstalled on Windows 11 and current Windows 10; see
[`docs/release-notes-windows.md`](docs/release-notes-windows.md) if Notebar fails to open a
note.

Source: `windows/Notebar.App` (the WinUI app), `windows/Notebar.Core` (the portable panel
state machine and models — the Windows counterpart to `NotebarCore` above, a separate
implementation of the same design, not shared code), `windows/Notebar.Store` (SQLite
storage, the counterpart to `NotebarStore`).

## License

Not yet chosen.
