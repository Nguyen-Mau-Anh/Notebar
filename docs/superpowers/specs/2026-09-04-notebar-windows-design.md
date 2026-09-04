# Notebar for Windows — Design Spec

- **Date:** 2026-09-04
- **Status:** Approved, autonomous build authorised through first release
- **Stack:** C# / .NET 9 · WinUI 3 (Windows App SDK) · Microsoft.Data.Sqlite · WebView2
- **Target:** Windows 11 22H2 or later, x64 and ARM64

---

## 1. Purpose

A Windows build of Notebar with the same behaviour, features, and visual design as the
shipped macOS app. The panel lives at the right screen edge, collapsed to a handle, expanding
on hover over whatever is in front — and it stays out of the way while the user is working.

**The macOS product spec ([2026-08-29-notebar-design.md](2026-08-29-notebar-design.md)) and
screen spec ([../../design/2026-08-29-screen-spec.md](../../design/2026-08-29-screen-spec.md))
remain the authority on what the app does and how it looks.** This document covers only what
differs because the platform differs. Where it is silent, those specs govern.

### Success criteria

1. Cursor rests on the handle, panel fully expanded and usable, in under 300 ms.
2. Capturing a note from any app requires no click on any window but Notebar's.
3. The panel never collapses while the user is typing, dragging, or has a menu open.
4. Idle cost under 1% CPU.
5. **No permission prompt, ever** — as on macOS, by construction rather than by policy.
6. Feature parity with macOS v0.2.2 at first release.

---

## 2. Decisions

Settled before this spec was written; recorded with reasoning because the reasoning is what
survives.

| Decision | Choice | Why |
|---|---|---|
| Data | **Independent database** | Each platform owns its own SQLite file. Sync is a larger project than this app; a synced folder holding a live SQLite file corrupts under concurrent access. |
| UI framework | **WinUI 3 + C#** | Microsoft's current native framework. Fluent maps onto the materials, radii, and accent treatment already designed. |
| Core logic | **Reimplemented in C#** | The Swift core is 328 lines of pure behaviour. A C ABI bridge to reuse it would cost more than the code it saves, permanently, and Swift has no Windows UI framework so the bridge is unavoidable in that approach. |
| Editor | **WebView2 + `contenteditable`** | Chips, checkboxes, lists, and images are ordinary HTML — the four things that were genuinely fiddly on macOS become free. |
| Body format | **HTML** | Portable. macOS can converge on it later, which is what would make sync possible. |
| Milestone shape | **One milestone, full parity** | The user's explicit choice, made with the downsides visible. Mitigated by ordering tasks platform-risk-first. |

### The RTFD blocker does not apply

Two earlier assessments called RTFD the expensive obstacle to Windows. That was true only
under the assumption that a Windows build must read macOS notes. **Independent databases mean
it never does** — the Windows app writes HTML from its first line and never encounters an
`NSAttributedString` serialization. Nothing needs migrating before this starts.

---

## 3. Architecture

Mirrors the macOS split, so the two products stay comparable and the conformance suite has
something to compare against.

```
windows/
├── Notebar.Core/            Pure C#. No UI, no platform types, no I/O.
│   ├── Panel/               PanelMachine, PanelState, EdgeZone, PanelTiming
│   ├── Models/              Note, TaskItem, Link, Theme, OpenTab, …
│   └── Repositories/        Interfaces only
├── Notebar.Core.Tests/      xUnit. The 46 Swift core tests, ported.
├── Notebar.Store/           Microsoft.Data.Sqlite. Schema, migrations, repositories.
├── Notebar.Store.Tests/     xUnit, against an in-memory database.
└── Notebar.App/             WinUI 3. Window, cursor, tray, hotkey, all views.
    └── Editor/              The contenteditable HTML page and its bridge.
```

**`Notebar.Core` takes no dependency on WinUI, WindowsAppSDK, or anything platform-specific.**
It is a plain `net9.0` library, buildable and testable on any machine — which is what lets the
logic be verified without Windows.

`Notebar.Store` targets `net9.0` and is likewise cross-platform; `Microsoft.Data.Sqlite` runs
anywhere. Only `Notebar.App` requires `net9.0-windows10.0.22621.0`.

### What can be verified where

| Project | Verified on | How |
|---|---|---|
| `Notebar.Core` + tests | macOS and CI | `dotnet test` |
| `Notebar.Store` + tests | macOS and CI | `dotnet test` |
| `Notebar.App` | **CI only** | `dotnet build` on `windows-latest` |

The development machine is a Mac. The WinUI layer cannot be built or run locally, so its
correctness rests on CI compilation and on the human running the released build. That is the
same division the macOS app used, where interaction defects were found by use rather than by
review — and it is stated here so nobody mistakes a green build for a working panel.

---

## 4. Platform capabilities

Four things the panel needs from the OS. All exist on Windows; **none requires a permission
prompt**, which is what preserves success criterion 5.

| Need | Windows API | Notes |
|---|---|---|
| Always-on-top borderless window | `AppWindow` + `SetWindowPos(HWND_TOPMOST)` via `Microsoft.UI.Win32Interop` | `OverlappedPresenter` with `SetBorderAndTitleBar(false, false)` |
| Present across virtual desktops | `IVirtualDesktopManager`, or re-assert topmost on desktop switch | The macOS analogue is `.canJoinAllSpaces` |
| Permission-free cursor polling | `GetCursorPos` | No prompt, no elevation. Direct analogue of `NSEvent.mouseLocation`. |
| System-wide hotkey | `RegisterHotKey` | No prompt. Direct analogue of Carbon `RegisterEventHotKey`. |
| Tray icon and menu | `Shell_NotifyIcon` | Replaces `NSStatusItem`. |

**Do not use low-level keyboard or mouse hooks** (`SetWindowsHookEx` with `WH_KEYBOARD_LL` or
`WH_MOUSE_LL`). They are unnecessary for all four needs, they trip antivirus heuristics, and
they are the Windows equivalent of the Accessibility permission this project has always
refused.

### Fullscreen behaviour

macOS `.fullScreenAuxiliary` has no exact counterpart. A topmost window generally draws over a
borderless-fullscreen app but not over an exclusive-fullscreen one (typically games). This is
a real behavioural difference from macOS and is accepted rather than worked around; document
it, do not fight it with hooks.

---

## 5. Data model

The same seven tables as macOS, same fractional `sort_order`, same generic `link` edge table.
The SQL ports verbatim — it is text.

**One change:** `note.body_html TEXT` replaces `body_rtf BLOB`. `body_plain` remains, derived
in the same transaction, and continues to feed FTS5. List markers and checkbox glyphs are
excluded from `body_plain` for the same reason they are on macOS: they are editor bookkeeping,
not text the user wrote.

Images are stored in an `attachment` table keyed by id and referenced from the HTML as
`<img src="https://notebar.local/asset/<id>">`, rather than embedded as data URIs. That URL
form rather than a custom `notebar-asset://` scheme because WebView2 serves it through
`AddWebResourceRequestedFilter` + `WebResourceRequested`, which hands the host a plain
request/response pair; registering a genuinely custom scheme requires far more ceremony for
the same result. macOS embeds them in
the RTFD blob and had to add a `summaries()` query to avoid loading them for list views; doing
it properly here costs nothing extra at the start.

Database location: `%LOCALAPPDATA%\Notebar\notebar.sqlite`.

---

## 6. Behaviour parity

`PanelMachine` is ported exactly: same four states, same events, same effects, same
`shouldCollapse` policy including all six suppression signals and the deliberate non-use of
`isWindowKey`. The timings are the values validated by use on macOS — 120 ms open dwell,
350 ms close dwell, 24 pt edge tolerance, 180/140 ms animations — and are user-adjustable in
Settings with the same clamping applied on read.

`EdgeZone` ports **verbatim, with no coordinate flip and no changed test numbers.** Windows
screen coordinates are top-left origin with y increasing downward, the opposite of Cocoa —
but every expression in `EdgeZone` is written in terms of a rect's min and max on each axis
(`MaxX - cursor.X`, `MinY <= cursor.Y <= MaxY`), and both coordinate systems have MinY..MaxY
spanning the screen. Only the *meaning* of MinY changes, from "bottom" to "top"; no arithmetic
does. The doc comment must be rewritten to say so, because the reason it ports cleanly is
non-obvious and the next reader will otherwise assume a flip was forgotten.

Panel geometry: 340 dip wide, 70% of the work area's height, vertically centred, flush to the
right edge, collapsing to a 30×56 handle. Maximize takes it to half the work-area width at
full height. All measurements are in device-independent pixels and must respect per-monitor
DPI.

---

## 7. Editor

A local HTML document in a WebView2, `contenteditable`, styled to the screen spec.

- **Formatting** — bold, italic, inline code, H1, H2, bulleted and numbered lists, checklists.
  All native HTML; no custom hit-testing, no marker bookkeeping, no glyph-availability
  problems.
- **Link chips** — `<a href="notebar://note/<id>">` with chip styling. Click is a navigation
  event the host intercepts.
- **Images** — `<img>` referencing the attachment store. Pasted images are downscaled above
  2000 px on the longest edge before storing.
- **Checkboxes** — `<input type="checkbox">`. Toggling is a DOM event.

**The bridge is the risk, not the editor.** The host must know: focus gained and lost, that a
keystroke happened (for `msSinceLastKeystroke`), that content changed (for the 400 ms
debounced save), and that a link was clicked. Use `WebView2.WebMessageReceived` in one
direction and `ExecuteScriptAsync` in the other, with a single typed message envelope rather
than ad-hoc strings.

Two traps carried from the macOS build:

- **Focus must be derivable, not just event-driven.** The macOS build had `isEditorFocused`
  stick `true` when a focused editor was destroyed, leaving the panel permanently
  un-collapsible. Reconcile it from something observable at the point the reducer reads it,
  the way macOS ended up reconciling against `firstResponder`.
- **Every collapse-suppression flag needs a clearing path that does not depend on the thing
  that set it still existing.** `isDragging` on macOS is cleared by a mouse-button poll for
  exactly this reason.

---

## 8. Testing

**The conformance suite is the load-bearing artifact.** The 46 macOS core tests port to xUnit
against `Notebar.Core`. If the C# `PanelMachine` passes the same assertions, it provably
behaves like the shipped Swift one, and divergence is caught rather than discovered.

Where a ported test must change — the `EdgeZone` y-axis flip — the change is explicit and
commented, never silent.

`Notebar.Store` gets its own suite against an in-memory database, mirroring the macOS store
tests: round-trips, `body_plain` synchronisation, FTS behaviour, fractional reordering,
`completed_at` lifecycle, and link cascade.

`Notebar.App` gets none. There is no test bundle for the WinUI layer, exactly as there is none
for the SwiftUI layer, and for the same reason: the defects that live there are interaction
defects that a human finds by using the app.

---

## 9. Packaging and release

- **MSIX**, unsigned for the first release, built in CI on `windows-latest`.
- Unsigned MSIX cannot be installed by double-click; the release notes must give the
  `Add-AppxPackage` command and explain the SmartScreen warning, in the same spirit as the
  macOS release notes explaining Gatekeeper.
- A **portable zip** of the unpackaged build is published alongside it, because it needs no
  installation ceremony at all and is the faster path to "does this work on my machine".
- Published as a GitHub release tagged `windows-v0.1.0`, so macOS and Windows versions do not
  collide in one tag sequence.

Code signing is out of scope. An EV certificate is roughly $300–500/year and, unlike Apple
notarization, is not required for the app to run — only to avoid SmartScreen's warning.

---

## 10. Out of scope

- Sync between platforms. The HTML body format keeps it possible; nothing here builds it.
- Code signing or Store distribution.
- Any change to the macOS app. It keeps shipping untouched.
- Windows 10. WinUI 3 supports it, but the design targets Win11's Fluent materials and the
  visual result on 10 is not specified here.
