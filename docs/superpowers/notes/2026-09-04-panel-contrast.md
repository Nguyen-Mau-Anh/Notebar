# Panel contrast: the panel washes out over a light background

Reported with a screenshot of the shipped macOS build: with a white window behind
the panel, the note tab labels and the formatting-bar icons are barely legible.
The rail survives; everything on the panel surface does not.

**Fixed.** The diagnosis below was written first; the section at the end records what the
arithmetic changed about the fix.

## macOS — the cause, confirmed in the code

Two things compound, and only the first is the root cause.

1. **The panel surface is a translucent material.** `EdgePanel` sets
   `isOpaque = false` and `backgroundColor = .clear`, so the window itself paints
   nothing, and `RootView` fills it with `.background(.regularMaterial)`
   (`RootView.swift:51`, and again at `:84`). A vibrancy material samples what is
   behind the window, so the panel's own surface luminance is set by the user's
   desktop rather than by the design. Over a white background the surface goes
   very light.

2. **Foreground content is deliberately de-emphasised.** Inactive tab labels and
   every formatting-bar icon use `Color.secondary`
   (`NotesTab.swift:180`, `FormattingBarView.swift:50`), which is roughly half the
   opacity of the label colour. That is correct against a *known* surface. Against
   a surface that can drift to near-white, it leaves almost no contrast headroom.

So the failure is not a wrong colour — it is a surface whose luminance is not
under the app's control, combined with foregrounds chosen as if it were.

## The fix, in order

1. **Make the panel surface opaque.** Replace `.regularMaterial` with a solid,
   appearance-aware surface colour. Contrast then stops depending on what the user
   happens to have open behind the panel. This is what the Windows build already
   does — see below — which is why Windows does not have this bug.
2. **Only then reconsider the foregrounds.** With a known surface, `Color.secondary`
   may well be fine; if it is not, raise the formatting-bar icons to `.primary`.
   Doing this *first* would mask the symptom while leaving the panel's appearance
   at the mercy of the desktop.

Losing the material costs some visual character. That is the trade: legibility on
every background beats translucency on some. If translucency is wanted back later,
it needs a scrim — an opaque-enough layer between the material and the content —
not a return to sampling the desktop directly.

## Windows — not affected, and here is the proof

`windows/Notebar.App/DesignSystem/Tokens.xaml` uses fully opaque surfaces
(`#FBFBFD` / `#242426`) and there is no `Mica`, `Acrylic` or `SystemBackdrop`
anywhere in the app, so nothing behind the window can bleed through.

Measured contrast against the panel surface:

| Brush | Light | Dark |
|---|---|---|
| `TextPrimaryBrush` | 16.28 | 14.23 |
| `TextSecondaryBrush` | 4.91 | 5.40 |
| `TextTertiaryBrush` | **2.49** | 3.06 |

## Windows — one real problem this surfaced, to fix before release

`TextTertiaryBrush` at **2.49:1** in light mode fails even the 3:1 threshold that
applies to large text and graphics. It is used in exactly three places:

- two 32pt empty-state `FontIcon`s (`RootPage.xaml:87`, `NotesTab.xaml:74`)
- `ChromeMicroTextStyle` — **10pt SemiBold text**, used for the rail's task-count
  badge (`RootPage.xaml:58`) and the all-notes menu's timestamps
  (`AllNotesMenu.xaml:49`)

10pt text at 2.49:1 is not readable for anyone who needs contrast, and it is the
smallest text in the app.

**Fix:**

1. Point `ChromeMicroTextStyle`'s foreground at `TextSecondaryBrush`. Small text
   earns the text-tier contrast (4.91 light / 5.40 dark); it does not need to be
   the faintest thing on screen to read as secondary.
2. Raise light `TextTertiaryBrush` from `#A1A1A6` to `#8E8E93` (3.15:1), so the
   tier that remains — 32pt decorative icons — clears the 3:1 bar that actually
   applies to graphics.

That splits the tiers by what they paint rather than by how faint they look: text
gets the text threshold, decoration gets the graphics threshold.


---

# What the arithmetic changed

The fix above says "make the panel surface opaque," and the screen spec §1 says something
subtly different: each surface is a flat tint composited **over** a material at a stated
opacity — 88% for the panel, 80% for the rail — so the material still supplies some
backdrop. That reads like the better answer: it keeps the vibrancy and bounds the drift.

It does not survive contact with the numbers. Composited against the worst-case backdrops
(pure white and pure black), `text.secondary` on the spec's own opacities lands at:

| surface | over white | over black |
|---|---|---|
| light panel, 88% | 4.91 OK | **3.74** large-text only |
| light rail, 80% | 4.74 OK | **2.91** fails AA |
| dark panel, 78% | **2.63** fails AA | 5.93 OK |
| dark rail, 70% | **2.12** fails AA | 6.36 OK |

The reported case is the last row: dark appearance, white window behind the panel, 2.12:1.
That is the screenshot.

Solving for the alpha that holds 4.5:1 in the worst case gives **0.92 to 0.99** depending on
the surface. At 0.99 the backdrop contributes one percent — there is no material left to
see. A translucency that has to be 99% opaque to be legible is not translucency, so the
material was dropped rather than kept as a decorative one percent.

## The alternative that was rejected

Keeping the material and raising every foreground from `text.secondary` to `text.primary`
also passes, comfortably (5.60 to 16.28). It was rejected on design grounds rather than
contrast: it flattens the secondary tier out of existence. An inactive tab would read
exactly like an active one, and the formatting bar would lose its "quiet until it applies
to your caret" affordance — the thing that makes a toolbar readable at a glance.

Losing the blur costs less than losing the hierarchy.

## What shipped

`Notebar/DesignSystem/Surface.swift` — `Tokens.Surface` with three opaque, appearance-aware
colours (rail, panel, elevated) taken from the spec's palette, resolved per appearance
through a dynamic `NSColor` so a light/dark switch is followed live rather than captured
once. All four material call sites now go through it, and no bare material remains in the
app.

Guaranteed contrast, independent of whatever is behind the panel:

| surface | `text.secondary` |
|---|---|
| light panel | 4.91 |
| light rail | 4.66 |
| dark panel | 5.40 |
| dark rail | 5.80 |

The Windows port already had opaque surfaces with these same values, which is why it never
had this defect — the two platforms now agree.
