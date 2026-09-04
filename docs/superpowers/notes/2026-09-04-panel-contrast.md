# Panel contrast: the panel washes out over a light background

Reported with a screenshot of the shipped macOS build: with a white window behind
the panel, the note tab labels and the formatting-bar icons are barely legible.
The rail survives; everything on the panel surface does not.

**To be fixed after the Windows milestone ships.** Diagnosis recorded now, while
the evidence is in hand.

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
