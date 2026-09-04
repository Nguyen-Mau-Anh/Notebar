# Reusing the logic for a Windows app: two approaches, and which one to take

The question: keep the business logic, write a new Windows app against it, same features.
Yes — but "keep the logic" has two implementations with very different costs, and the
measurement points clearly at one.

## What is actually reusable, measured

`NotebarCore` is 1,426 lines, and it is not one thing. It is three, with very different
value:

| | Lines | What it is | Cost to recreate |
|---|---|---|---|
| **Panel behaviour** | **328** | `PanelMachine`, `PanelState`, `EdgeZone`, `PanelTiming` | **High.** Hard-won, tuned by use, 46 tests. |
| Models | ~530 | `Note`, `TaskItem`, `Link`, `Theme`, `OpenTab`, … | Trivial. Data structures. |
| Schemas + protocols | ~560 | SQL strings and interfaces | Trivial. The SQL ports verbatim as text. |

The genuinely irreplaceable asset is **328 lines** — the state machine, the edge geometry,
the collapse-suppression policy, and the timings the user validated by feel. Everything else
is a data structure or a string.

Its 388 lines of tests matter as much as the code: they are an executable specification of
how the panel must behave, including every flicker case found the hard way.

The app is 5,075 lines and none of it ports: 683 lines of platform glue (window, cursor
polling), 3,972 of SwiftUI, 420 of lifecycle and tray.

## Approach A — compile the Swift core, call it from a C# UI

Swift for Windows works; CI now proves `NotebarCore` compiles and passes its tests there.
So this is possible.

But Swift has no viable UI framework on Windows, so the UI is C# or C++ regardless — which
means a **C ABI bridge is mandatory**, not optional. That bridge has to marshal structs,
strings, arrays, and callbacks in both directions, and every Windows developer needs a Swift
toolchain to build the app.

**All of that to reuse 328 lines of pure functions.** The bridge would plausibly cost more
than the code it saves, and it is a permanent tax on every future change rather than a
one-off.

## Approach B — reimplement the core in C#, using the tests as the specification

Port those 328 lines and their 388 lines of tests to C#. `PanelMachine.reduce` is a pure
function over an enum; `EdgeZone` is arithmetic; `PanelTiming` is constants. There is nothing
in any of it that resists translation.

The schemas port verbatim — they are SQL strings.

**The tests are the real deliverable.** Ported to C#, they become a conformance suite: if the
C# `PanelMachine` passes the same 46 assertions, it behaves identically to the macOS one, and
divergence is caught rather than discovered.

Cost: two implementations to keep in sync. Mitigated by the fact that this core has been
stable — its behaviour was settled during M0 and has barely changed since.

## Recommendation: B

Not because Swift-on-Windows fails — it demonstrably works — but because the interop layer
costs more than the 328 lines it would save, and imposes that cost forever.

Reimplement, and treat the Swift core as the reference implementation plus a conformance
suite.

## The most valuable thing to carry over is not code

The specs are worth more than either option's source. `docs/superpowers/specs/` records
decisions that took a full session of building and user testing to arrive at:

- the **six collapse-suppression signals**, and why `isWindowKey` is deliberately unused
- the timings — 120 ms open, 350 ms close, 24 pt slop — **validated by use**, not chosen
- the trigger band being the handle's exact frame, after a wider band caused accidental opens
- the drop target covering a group's header, because empty columns are otherwise unreachable
- flushing pending saves on terminate, so quitting never loses the last thing typed
- hit-testing needing an explicit shape, learned from clicks that silently did nothing

A Windows implementation that ignores those will rediscover each one as a bug report.

## Order of work

1. **Move note bodies off RTFD.** Still the blocker, still gets more expensive with every
   note, and worth doing on macOS alone. Nothing else can start meaningfully until the data
   is readable by a non-Apple process.
2. **Port the 328 lines and their tests to C#.** Days, not weeks. Ends with a conformance
   suite proving equivalence.
3. **Storage.** SQL ports verbatim; pick any Windows SQLite binding behind the same
   repository interfaces.
4. **The app.** WinUI 3. The four platform capabilities it needs — always-on-top borderless
   window, permission-free cursor polling, a global hotkey, a tray icon — all exist on
   Windows and none are exotic.
5. **Installer in CI.** MSIX or WiX. Windows runners are free on a public repo. This is a
   day, and it is last for a reason.

## Scope, honestly

Steps 2 through 5 are a multi-week project for one person. This is not a milestone that fits
alongside macOS feature work — it is a second product sharing a specification.

The macOS app should keep shipping either way. Step 1 is the only item that benefits both,
and it is the only one worth doing before someone actually needs Windows.
