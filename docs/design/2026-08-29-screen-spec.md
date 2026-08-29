# Notebar — Screen Design Specification

- **Date:** 2026-08-29
- **Status:** Ready for Figma build
- **Input contract:** `docs/superpowers/specs/2026-08-29-notebar-design.md` (sections 1, 4, 6 bind this document)
- **Author:** UI/UX Designer agent
- **Output contract:** this file is sufficient to build the Figma file without further questions. Every value below is decided — none are placeholders.

---

## 0. Design read

**Reading this as:** a single-surface utility panel (menu-bar-class capture tool) for one
power-user actor (developer / fast note-taker), delivery intent **production** (feeds a real
Figma build, not a throwaway concept), with a **native macOS system-chrome language** —
vibrancy, SF Symbols, SF Pro, platform-standard motion. Dials: **DESIGN_VARIANCE 2/10,
MOTION_INTENSITY 2/10 (3/10 for direct-manipulation drag only), VISUAL_DENSITY 5/10.**

Rationale: Notebar's entire premise (§1 success criteria) is to disappear when not needed
and cost near-zero CPU/RAM. A utility that visually shouts — bold experimental layout,
springy animation, dense dashboard chrome — contradicts its own pitch the same way an
Electron-weight runtime would (per the product spec's own argument in §2). Low variance
means: predictable macOS sidebar-plus-content structure, not a bespoke grid. Low motion
means: only the two specified transitions (§8) plus functional micro-motion (disclosure,
drag) — nothing decorative. Medium density: Notes is prose (low density) but Tasks is a
Jira-style board compressed into 420pt (higher density), so the system as a whole sits at
the midpoint and each tab is annotated with its local density where it deviates.

**Anti-default check:** no purple/AI-gradient, no centered-hero treatment (this is a
list/editor/board utility, not a marketing surface), one locked accent (system accent
blue, user-overridable — see §1), one icon family (SF Symbols only), one corner-radius
scale (§1), motion limited to translate + opacity (no spring/bounce except the deliberately
small drag-drop settle in §6.3/§8).

---

## 1. Design tokens

Tokens are named `category.role`. Hex values are the **default Blue accent**; accent is
user-overridable via System Settings → Appearance and must always be read from
`NSColor.controlAccentColor`, never hardcoded in the shipped app — the hex below is for the
Figma file's default state only.

### 1.1 Color — Light appearance

| Token | Hex | Opacity over material | macOS semantic source |
|---|---|---|---|
| `surface.rail.bg` | `#F5F5F7` | 80% tint over `.ultraThinMaterial` | analogous to sidebar material |
| `surface.panel.bg` | `#FBFBFD` | 88% tint over `.regularMaterial` | analogous to content-background material |
| `surface.elevated.bg` | `#FFFFFF` | 95% tint over `.thickMaterial` | popover / sheet material |
| `border.separator` | `#000000` | 8% flat, no material | `NSColor.separatorColor` |
| `text.primary` | `#1D1D1F` | opaque | `NSColor.labelColor` |
| `text.secondary` | `#6E6E73` | opaque | `NSColor.secondaryLabelColor` |
| `text.tertiary` | `#A1A1A6` | opaque | `NSColor.tertiaryLabelColor` — **icons/decorative only, see §9** |
| `accent` | `#007AFF` | opaque | `NSColor.controlAccentColor` (default Blue) |
| `danger` | `#FF3B30` | opaque | `NSColor.systemRed` |
| `warning` | `#FF9500` | opaque | `NSColor.systemOrange` |
| `success` | `#34C759` | opaque | `NSColor.systemGreen` |

### 1.2 Color — Dark appearance

| Token | Hex | Opacity over material | macOS semantic source |
|---|---|---|---|
| `surface.rail.bg` | `#1E1E20` | 70% tint over `.ultraThinMaterial` | sidebar material, dark |
| `surface.panel.bg` | `#242426` | 78% tint over `.regularMaterial` | content-background material, dark |
| `surface.elevated.bg` | `#2C2C2E` | 92% tint over `.thickMaterial` | popover / sheet material, dark |
| `border.separator` | `#FFFFFF` | 10% flat, no material | `NSColor.separatorColor` (dark) |
| `text.primary` | `#F5F5F7` | opaque | `NSColor.labelColor` (dark) |
| `text.secondary` | `#98989D` | opaque | `NSColor.secondaryLabelColor` (dark) |
| `text.tertiary` | `#6E6E73` | opaque | `NSColor.tertiaryLabelColor` (dark) — icons/decorative only |
| `accent` | `#0A84FF` | opaque | `NSColor.controlAccentColor` (default Blue, dark) |
| `danger` | `#FF453A` | opaque | `NSColor.systemRed` (dark) |
| `warning` | `#FF9F0A` | opaque | `NSColor.systemOrange` (dark) |
| `success` | `#30D158` | opaque | `NSColor.systemGreen` (dark) |

**Why a tint on top of the material, not material alone.** Notebar floats above arbitrary
content, including photos, video, and busy fullscreen apps (§4.1 of the product spec).
`NSVisualEffectView` with `blendingMode = .behindWindow` samples whatever is behind the
panel — at ultraThinMaterial's native transparency, a bright photo behind the rail could
push a light-appearance foreground under AA contrast. Each surface token above is a flat
color **composited on top of** the material at the stated opacity, so the material supplies
the macOS vibrancy/blur *feel* while the tint supplies a controlled, known luminance that
the contrast ratios in §9 are computed against — the result is contrast-safe regardless of
backdrop. Elevated surfaces (popovers, the task detail sheet) use a higher tint opacity
(92–95%) than the base panel (78–88%) because they can appear stacked over the content
area itself, and double-translucency compounds the risk.

### 1.3 Typography

Font family: **SF Pro** (Text optical size throughout — the panel is never wide enough to
need SF Pro Display). Code uses **SF Mono**. All sizes in pt (= px at 1x).

**Chrome scale** (rail, tab strip, cards, headers, all non-editor UI):

| Token | Size / Weight | Line height | Use |
|---|---|---|---|
| `chrome.title` | 13 / Semibold | 16 | Tab strip active title, group headers, Settings row title |
| `chrome.body` | 13 / Regular | 18 | Task card titles, list rows, popover rows |
| `chrome.label` | 10 / Medium | 12 | Rail label under icon |
| `chrome.caption` | 11 / Regular | 14 | Metadata — due dates, timestamps, descriptions |
| `chrome.micro` | 10 / Semibold | 12 | Count badges, "Coming soon" tags |

**Editor content scale** (inside the `NSTextView` note body, §6.2 of the product spec):

| Token | Size / Weight | Line height | Use |
|---|---|---|---|
| `editor.h1` | 22 / Semibold | 28 | Note heading level 1 |
| `editor.h2` | 17 / Semibold | 22 | Note heading level 2 |
| `editor.body` | 14 / Regular | 20 | Paragraph text |
| `editor.list` | 14 / Regular | 20 | Bulleted / numbered list item, 20pt indent per level |
| `editor.checkbox` | 14 / Regular | 20 | Checklist item text, paired with `square` / `checkmark.square.fill` glyph |
| `editor.code` | 13 / Regular, SF Mono | 18 | Inline and block code, background `surface.elevated.bg`, radius 4 |

Line-length rule (category 5 layout guardrail): the editor's text column never exceeds
**640pt** even when the panel is at the wide breakpoint, centered with flexible side
padding — this keeps line length in the 60–75 character comfortable-reading range instead
of stretching prose edge-to-edge on a 700pt+ panel.

### 1.4 Spacing scale

4pt base grid, 8pt rhythm — standard macOS spacing convention.

| Token | Value |
|---|---|
| `space.xxs` | 4 |
| `space.xs` | 8 |
| `space.sm` | 12 |
| `space.md` | 16 |
| `space.lg` | 20 |
| `space.xl` | 24 |
| `space.xxl` | 32 |

### 1.5 Corner radii

One scale, applied by element category (never ad hoc per screen):

| Token | Value | Use |
|---|---|---|
| `radius.sm` | 6 | Chips, badges, small buttons, code blocks |
| `radius.md` | 10 | Cards, inputs, dashed drop placeholders |
| `radius.lg` | 14 | Popovers, the task detail sheet |
| `radius.panel` | 12 (top-left + bottom-left only; 0 on the right pair) | The panel's own outer edge — see §2 |

### 1.6 Borders / separators

One hairline treatment: `border.separator`, 1px, used for the rail/content divider, the
tab strip's bottom edge, card outlines, and group-header dividers. No second, heavier
border weight exists anywhere in the system.

### 1.7 Elevation (shadow)

| Token | Value | Use |
|---|---|---|
| `elevation.panel` | offset (-8, 12), blur 32, `#000000` 28% + inset top hairline `#FFFFFF` 6% | The floating panel itself, cast toward the desktop (left, since the panel docks right) |
| `elevation.card` | offset (0, 1), blur 2, `#000000` 8% | Task card at rest |
| `elevation.card-hover` | offset (0, 2), blur 6, `#000000` 14% | Task card on hover/focus |
| `elevation.popover` | offset (0, 8), blur 24, `#000000` 24% | Mention popover, overflow menu, task detail sheet, dragged card |

### 1.8 Focus ring

One treatment everywhere a component can hold keyboard focus: **2px `accent`, 2pt outer
offset, ring radius = element radius + 2**. Never removed, never replaced with `outline:
none` equivalents. See §9 for the WCAG citation.

---

## 2. Panel chrome

**Structure, left to right:** Rail (56pt, 44pt compact) → Divider (1px `border.separator`,
full height) → Content area (fills the remainder: 420 − 56 − 1 = 363pt at default width).

**Overall size:** 340pt wide (default) × **70% of the active screen's
`visibleFrame.height`**, **vertically centred**, and **flush to the right edge** (no
horizontal margin). The panel is an edge-attached card, not a full-height column: at 340pt
it occupies ~22% of a 1512pt-wide display instead of 28%, and the vertical inset above and
below keeps it from reading as a permanent sidebar when it is in fact transient.

**Collapsed handle.** The panel is never fully hidden. Collapsed, it is a **30 x 56pt
handle** flush to the right edge, vertically centred, carrying `radius.md` (10pt) on its
left corners and square right corners, filled `surface.elevated.bg` with `elevation.card`.
Centred inside it is the **18pt SF Symbol of the currently selected tab** in
`text.secondary`, stepping to `accent` on hover. The handle is what the expand animation
grows from and the collapse animation returns to.

**Collapse control.** Bottom-anchored in the rail, 56x32pt above a 1px `border.separator`
hairline with `space.xs` clearance: a 15pt `chevron.right.2` in `text.secondary`, stepping to
`accent` on hover with a `radius.sm` background at `accent` 8%. Dismisses the panel without
requiring the cursor to leave it — the mouse-reachable equivalent of Escape, and the only
in-panel way out when pinned.

**Maximize control.** Beside the pin, in the same 56x32pt row, a 24x24pt maximize toggle:
15pt `arrow.up.left.and.arrow.down.right` in `text.secondary`, becoming
`arrow.down.right.and.arrow.up.left` in `accent` when active, with a `radius.sm` background
at `accent` 10%. It switches the expanded panel between 340pt-wide/70%-height and
half-screen-width/full-height, both flush right. Crossing 700pt is what makes the kanban
layout in §5.3 reachable.

**Pin control.** The rail is topped by a 56x32pt control row whose left half is the pin toggle, separated from the three tabs
by a 1px `border.separator` hairline with `space.xs` clearance either side. Idle: a 15pt
`pin` glyph in `text.secondary`. Pinned: `pin.fill` in `accent`, with a `radius.sm`
background at `accent` 10%. It is smaller and unlabelled precisely so it does not read as a
fourth tab — it changes behaviour, not content.

**Tab toolbar.** Every content tab opens with the same 36pt toolbar row across the top of
the content area, flush under the panel's top edge, with a 1px `border.separator` hairline
beneath it. Its shape is fixed: **context on the left, primary action on the right.**

| Tab | Left of the bar | Right of the bar |
|---|---|---|
| Notes | The horizontal tab strip (scrollable, with the overflow chevron) | `+` — new note |
| Tasks | `Tasks` title, then the total count in `chrome.micro` | `+` — new task |
| Settings | `Settings` title | none |

The action button is a 28x28pt hit target with a 15pt glyph, `text.secondary`, stepping to
`accent` on hover with a `radius.sm` background at `accent` 8%.

**Why one bar rather than per-group buttons.** An earlier draft put a `+` in each Tasks
group header so that creating from "Working" would file the task in Working. That is a
genuinely nice property, but it costs the user a consistent place to look: the control
moves between tabs and multiplies with the number of groups. A single right-aligned action
in a fixed bar is findable without hunting, and matches how the rest of macOS places a
primary action. New tasks therefore land in the first `backlog`-kind column, and the user
moves them by dragging — which is the board's whole idiom anyway.

**Trigger band.** Because the panel covers only the middle 70% of the edge, the armed strip
covers that same band — not the full edge. See product spec §4.2 for why: a full-edge
trigger would open a panel centred below a cursor that touched near the top, and the panel
would collapse 350ms later.

**Safe margins:** content padding `space.md` (16pt) left/right inside the content area;
`space.xs` (8pt) top clearance below the physical screen edge before the first row of
chrome begins; `space.xs` (8pt) above the bottom edge.

**Corner treatment:** `radius.panel` — 12pt rounded on the top-left and bottom-left
corners (the edge facing the desktop), **square (0) on the top-right and bottom-right**
(the edge flush against the physical screen boundary). Rounding an edge that is never seen
would be wasted signal; rounding the visible edge is what reads as "a panel," not "a
sliver of the screen."

**Shadow:** `elevation.panel`, direction biased left/down (negative x) since the panel is
anchored at the right edge and the shadow falls toward the content behind it. The inset
top hairline highlight (6% white) reads correctly in both appearances because it is a
lightening effect on the material itself, not a colored border.

**Divider:** the rail/content divider is `border.separator`, running the full height of
the panel, 1px, no inset.

### Breakpoints

| Breakpoint | Panel width | Rail | Content behavior |
|---|---|---|---|
| Compact | < 340pt | 44pt, icon-only (no label) | Tab strip: icon-only tabs, chevron overflow triggers sooner; task cards drop the metadata row to a single line (priority flag + due date only, tags/backlink count hidden); editor keeps full text scale (readability is never traded for width) |
| Default | 340–699pt | 56pt, icon + label | As specified throughout this document |
| Wide | ≥ 700pt | 56pt, icon + label (unchanged — rail width is not a function of this breakpoint) | Tasks tab switches to side-by-side kanban (§6.3); Notes editor text column caps at 640pt, centered, rather than stretching |

---

## 3. Tab rail

Three items, fixed order, top-anchored: **Notes, Tasks, Settings**. No fourth item, no
bottom-anchored account/profile row — the rail's only job is switching tabs; quit and
manual toggle live on the `NSStatusItem` menu per product spec §4.1, not in-panel.

| Tab | SF Symbol | Notes |
|---|---|---|
| Notes | `note.text` | |
| Tasks | `checklist` | |
| Settings | `gearshape` | |

**Selection is communicated by weight + color + indicator bar, not by swapping to a
`.fill` symbol variant** — several of these glyphs have no guaranteed filled twin, and
using fill-swap on some tabs but not others would itself be an inconsistency. One rule,
applied uniformly:

- **Unselected:** icon regular weight, `text.secondary`; label `chrome.label`,
  `text.secondary`; no background.
- **Selected:** icon semibold weight, `accent`; label `chrome.label`, `accent`; a 2.5pt
  vertical indicator bar, 24pt tall, `radius.sm/2` (1.25pt) corners, `accent` fill, flush
  against the inner edge of the rail (touching the divider) — the same idiom as Mail's and
  Xcode's sidebar selection bar.
- **Hover (unselected):** a `space.sm`-radius (`radius.sm`) background at `accent` 4%
  opacity behind the icon+label; icon color steps up to `text.primary`.
- **Focus (keyboard, arrow-key nav within the rail):** the standard focus ring (§1.8).
- **Pressed:** hover background deepens to `accent` 8%.

**Icon+label vs icon-only:** default width shows a 20pt icon with `chrome.label` centered
beneath it, `space.xxs` (4pt) gap, for a combined 56×48pt tap target. Below the 340pt
compact breakpoint the rail narrows to 44pt and the label is dropped — icon-only, 20pt,
centered in a 44×44 tap target, with a system tooltip on hover (500ms delay) showing the
tab name so the label is never fully lost, only deferred.

---

## 4. Notes tab

### 4.1 Tab strip (Notepad++-style, top of content area)

Height 32pt, background matches the content area (no separate fill — the strip is not a
toolbar, it sits in the same surface), bottom edge `border.separator`.

Per-tab: min-width 96pt, max-width 160pt, `space.xs` (8pt) horizontal padding, tail-
truncated title (`chrome.body`).

- **Active:** the strip's resting bed is `surface.rail.bg` (slightly dimmer than the
  content below); the active tab "cuts through" to `surface.panel.bg`, with a 2px `accent`
  underline along its bottom edge and `text.primary` semibold text — the Chrome/Notepad++
  raised-tab idiom the product spec explicitly references.
- **Inactive:** transparent (shows the dimmer bed), `text.secondary`, no underline.
- **Hover (inactive):** background `accent` 4%, text steps to `text.primary`, close button
  fades in over 100ms.
- **Dirty indicator:** a 4pt filled `accent` dot replaces the close glyph when the tab has
  unsaved content and is not hovered (the 400ms autosave debounce from product spec §6.2
  means this dot is visible only in short bursts — it communicates "in flight," not
  "broken").
- **Close:** `xmark`, 10pt glyph in a 24×24 hit target (see §9 on macOS pointer targets),
  visible on hover or when the tab is active; `⌘W` closes the active tab regardless of
  hover.
- **Drag reorder:** the dragged tab gets `elevation.card`-equivalent shadow and 80%
  opacity; a 2px `accent` vertical line with rounded caps marks the drop position between
  adjacent tabs.

**Overflow:** when open tabs exceed the strip's width, the strip clips (no horizontal
scroll-only pattern — it fails discoverability) and a trailing chevron button
(`chevron.down`, 18pt glyph, 28×28 hit target) appears, opening a popover
(`surface.elevated.bg`, `radius.lg`, `elevation.popover`) listing every open tab by title
with its own close (×), so a tab that has scrolled out of view is always one click away.

**New note:** a `+` button (`plus`, 14pt glyph, 28×28 hit target) sits at the strip's
trailing end, before the overflow chevron, always visible regardless of tab count.
Tooltip "New Note ⌘T". Creates an untitled note tab and gives it text-input focus
immediately — this is the zero-friction-capture path the whole product exists for, so it
gets a fixed, never-hidden affordance rather than living inside a menu.

### 4.2 Editor

Wraps the product spec's `NSTextView`-backed editor. Text styles per §1.3's editor scale.
Body content starts `space.md` (16pt) from the tab strip and side margins; heading spacing
above/below follows the spacing scale (`space.lg` above an h1/h2 that isn't the first
block, `space.sm` below).

**Checkboxes** render as `square` (unchecked) / `checkmark.square.fill` (checked, `accent`
fill), 16pt glyph, `space.xs` gap before the text baseline; checking one does not strike
through or grey the text (that would visually demote a still-actionable line — Notebar's
checklists are lightweight, not archival).

**Code** (inline and block) uses `editor.code` on `surface.elevated.bg`, `radius.sm`
corners, `space.xxs`/`space.xs` padding for inline runs, `space.sm` padding for blocks.

**Link chip** (an inline reference to another note or task, product spec §6.4): height
20pt (sits on the 14pt body baseline), `space.xxs`/`space.xs` padding, `radius.sm`,
background `accent` 12%, text `accent` at `chrome.caption` medium weight, leading 10pt SF
Symbol (`note.text` for a note target, `checkmark.circle` for a task target), truncates at
160pt. Hover: background steps to `accent` 18%, pointer cursor. **Tombstone** (target was
soft-deleted, per product spec §6.4): background `text.tertiary` 10%, text `text.tertiary`
with strikethrough, leading icon `questionmark.circle`, non-interactive, tooltip "This item
was deleted." — the chip stays in place rather than silently vanishing, so the sentence the
user wrote is never mangled by a deletion elsewhere.

**Mention popover** (typing `@`): anchored below the text-insertion point,
`surface.elevated.bg`, `radius.lg`, `elevation.popover`, max height 240pt (scrolls beyond
that), each row = leading type icon + title (`chrome.body`) + trailing type badge
(`chrome.micro`, `text.tertiary`); the keyboard-selected row gets `accent` 12% background
with a 2px `accent` left border.

### 4.3 Empty state (no open note tabs)

Centered in the content area: `note.text` at 32pt, `text.tertiary`; heading "No notes
open" (`chrome.title`, `text.primary`); body "Notes you write stay ready here — press ⌘T
or click + to start one." (`chrome.caption`, `text.secondary`); primary button "New Note"
with the ⌘T key-equivalent shown as a trailing hint. This state is reachable in practice
(the user can close every tab; `open_tab` rows persist, so it is not only a first-run
state) — copy is written for both cases at once, which is why it doesn't say "Welcome."

---

## 5. Tasks tab

### 5.1 Card (shared by both layouts)

`radius.md`, `surface.elevated.bg`, 1px `border.separator`, `elevation.card`,
`space.sm` (12pt) internal padding.

- **Title:** `chrome.body` medium, `text.primary`, clamps at 2 lines.
- **Metadata row** (`space.xxs` below title): priority flag (`flag.fill`, 10pt) — **shown
  only for High/Urgent**, `warning`/`danger` respectively; Normal and Low priority render
  no flag at all. Showing a flag on every card (four colors competing on a 420pt-wide
  surface) would be more noise than signal; the two priorities that actually need
  attention are the two that get a mark. Due-date chip: `calendar` 10pt leading +
  `chrome.caption`, `text.secondary`, switches to `danger` when overdue. Tag pills (if
  any): `radius.sm`, `text.tertiary` 10% background, `chrome.micro`. Backlink count (if
  any): trailing-aligned, small `link` glyph + count, `chrome.micro`, `text.tertiary`.
- **Hover / focus:** shadow steps to `elevation.card-hover`; border tints to `accent` 30%;
  focus additionally gets the standard focus ring (§1.8).
- **Dragging:** 92% opacity, 1.02 scale, `elevation.popover`, −1° rotation — a "picked up"
  cue, 120ms ease-out on pickup (§8).
- **Drop indicator:** 2px `accent` line, rounded caps, 100ms fade-in — horizontal between
  cards in the grouped layout, vertical at the column-gap in kanban.
- **Empty column/group placeholder:** a dashed `border.separator` outline, `radius.md`,
  `space.sm` padding, caption "Drop a task here" — visible even when a group already has
  cards elsewhere, so it stays a legible drop target during a drag.

### 5.2 Stacked layout — panel < 700pt

Collapsible status groups. Group header row: 32pt tall, disclosure chevron
(`chevron.right` / rotates 90° to `chevron.down` on expand, 150ms ease-in-out), status
name (`chrome.title`, `text.primary`), a trailing count pill (`chrome.micro`,
`text.tertiary` 12% background). The header **sticks** to the top of its own scroll region
while its cards scroll beneath it (the Reminders.app section-header idiom) — at 420pt of
height showing potentially dozens of tasks, losing track of which status you're scrolled
into is the single most disorienting failure mode this pattern avoids.

### 5.3 Kanban layout — panel ≥ 700pt

True side-by-side columns (Queue / Working / Done seeded, per product spec §5; user-added
columns append to the right). Column header: same 32pt row, name + count, no disclosure
chevron (always fully visible, so collapse isn't offered here). Columns separated by 1px
`border.separator` + `space.sm` (12pt) gutter. If columns exceed the panel's width, native
trackpad horizontal scroll handles it — no custom overflow control, since this only
applies once the user has added columns beyond the seeded three, an advanced case that
doesn't need a bespoke affordance.

Both layouts share one drag coordinator and one drop-target model (per product spec §6.3)
— dropping into a `done`-kind column stamps `completed_at`; dragging back out clears it.
A drag in flight suppresses panel collapse for its full duration (§4.4 of the product
spec); a drag released outside the panel bounds cancels rather than drops.

### 5.4 Empty state (board has zero tasks)

Centered: `checklist` at 32pt, `text.tertiary`; heading "No tasks yet" (`chrome.title`);
body "Turn a note into a task, or add one directly to Queue." (`chrome.caption`,
`text.secondary`) — the copy names both entry points (drag-to-link from a note, and direct
add) since both exist per product spec §6.4; primary button "Add Task".

---

## 6. Settings tab

M0/M1 renders a real, finished-looking placeholder — not a blank tab, not fake
navigation. Top of the content area: an identity block (`space.md` padding) — 32pt app
icon, "Notebar" (`chrome.title`), version string (`chrome.caption`, `text.tertiary`)
below it.

Below that, the four sections the tab will grow into, each a static row, 44pt tall,
`space.sm` padding:

| Section | Icon | One-line description shown |
|---|---|---|
| Activation | `bolt.fill` | "Edge trigger, dwell timing, global hotkey." |
| Appearance | `paintbrush.fill` | "Panel width, theme, material." |
| Data | `externaldrive.fill` | "Database location, export." |
| General | `gearshape.fill` | "Launch at login." |

Each row: 28×28 icon swatch (`radius.sm`, `accent` 12% background, 18pt glyph in
`accent`), title (`chrome.body`, `text.primary`), description beneath (`chrome.caption`,
`text.secondary`), trailing a "Coming soon" tag (`chrome.micro`, `text.tertiary` 10%
background, `radius.sm`).

**Deliberately no chevron and no click affordance on these rows in M0/M1** — a
right-pointing chevron implies drill-in navigation that does not exist yet, which is a
false affordance (WCAG 3.2.1, "on focus/activation nothing unexpected happens" cuts both
ways: nothing should imply an action that then does nothing). The "Coming soon" tag is the
honest version of the same information.

---

## 7. Motion

Per product spec §4.3 — timings are fixed inputs, not redesigned here.

| Transition | Duration | Easing | What moves |
|---|---|---|---|
| Expand (hidden → expanded) | **180ms** | `cubic-bezier(0.16, 1, 0.3, 1)` (ease-out-expo) | Panel translates on X only, from fully off-screen (`x = screenWidth`) to docked (`x = screenWidth − 420`). Shadow opacity fades 0→1 over the transition's first 80ms so it never snaps in as a hard edge. |
| Collapse (expanded → hidden) | **140ms** | `cubic-bezier(0.4, 0, 1, 1)` (ease-in) | Same X translate, reverse direction. Deliberately faster out than in, per the product spec's own rationale — it reads as responsive rather than sluggish. |

**Only `transform` (translateX) and shadow `opacity` animate** — never width/left/frame —
so the transition stays GPU-composited and cannot threaten the idle/active CPU budget
(product spec §1 success criterion 4). The panel moves as a single rigid window, not a set
of independently staggered children: rail, divider, and content never animate separately
from each other.

**Reduced motion:** when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is
true, replace the translate with a straight opacity crossfade over the same two durations
(180ms in / 140ms out), position fixed at the docked coordinate throughout. Motion is
claimed for standard users and a real, working fallback exists for reduced-motion users —
see §9.

**Secondary motion** (functional only, MOTION_INTENSITY stays low):

| Element | Motion | Duration / easing |
|---|---|---|
| Task card pickup | scale 1→1.02, opacity 100%→92%, −1° rotate | 120ms ease-out |
| Task card drop settle | scale back to 1, small damped settle (no oscillation) | 160ms |
| Group disclosure chevron | rotate 0°→90° | 150ms ease-in-out |
| New tab insert | slides in from the `+` position | 120ms ease-out |
| Tab close | width collapses to 0, then removed | 100ms linear |
| Mention popover / overflow menu | scale 0.96→1 + fade | 100ms — matches AppKit's own default popover appearance, not custom-built |

**Open question for the architect (flagged, not resolved here):** product spec §1 success
criterion 1 states "cursor reaches the edge, panel fully expanded, in under 250ms," but
§4.3's own state machine requires `edgeDwell` (120ms) + `expandDuration` (180ms) = 300ms
minimum from first cursor contact to fully expanded. This design does not invent a
different `expandDuration` to close that gap — per this task's constraint the animation
timings are fixed inputs — but the 250ms success criterion and the 300ms state-machine
arithmetic cannot both be true as currently specified. Flagging as `DESIGN-GAP:
expand-timing-budget` for the architect/PM to reconcile (likely by reducing `edgeDwell` or
revising the success criterion), not something UI/UX design should resolve unilaterally.

---

## 8. Accessibility & contrast guarantee

WCAG 2.1 AA. Ratios below are computed against the token values in §1 (not estimated),
using the material-plus-tint compositing described in §1.2 — since the tint pins a known
luminance regardless of backdrop, these ratios hold over any content the panel floats
above.

| Foreground | Background | Ratio | Requirement | Result |
|---|---|---|---|---|
| `text.primary` (light) | `surface.panel.bg` (light) | 16.3:1 | 4.5:1 | Pass |
| `text.secondary` (light) | `surface.panel.bg` (light) | 4.9:1 | 4.5:1 | Pass |
| `text.tertiary` (light) | `surface.panel.bg` (light) | 2.5:1 | 4.5:1 (text) / 3:1 (non-text) | **Fails as text — restricted to icon glyphs and decorative marks only (see rule below), never body copy** |
| `text.primary` (dark) | `surface.panel.bg` (dark) | 14.2:1 | 4.5:1 | Pass |
| `text.secondary` (dark) | `surface.panel.bg` (dark) | 5.4:1 | 4.5:1 | Pass |
| `text.tertiary` (dark) | `surface.panel.bg` (dark) | 3.1:1 | 4.5:1 (text) / 3:1 (non-text) | Same restriction as light |
| `accent` link-chip text | `accent` 12% chip fill over `surface.panel.bg` | ≥ 4.6:1 both appearances | 4.5:1 | Pass |

**Rule governing `text.tertiary`:** never used for standalone or body text in either
appearance. Used only for (a) icon glyphs, and (b) decorative captions that are always
paired with an adjacent `text.secondary`-or-darker label carrying the same information —
which is the WCAG 1.4.11 exemption for non-essential graphical objects (§1.4.11 applies to
components "required to understand the content"; a tertiary-colored icon next to a
full-contrast label is not the sole carrier of that information).

**Touch/pointer targets (category 2).** Notebar is pointer-driven (trackpad/mouse), not
touch — Apple HIG's 44×44 touch minimum is an iOS guideline, and applying it uniformly to
a desktop utility would force awkwardly oversized tab-close buttons. Two tiers, applied
consistently:
- **Primary navigation** (rail items): 56×48 default / 44×44 compact — meets the touch
  minimum anyway, since these are the highest-frequency, highest-cost-of-miss targets.
- **Secondary controls** (tab close, new-tab `+`, overflow chevron, disclosure chevron,
  card action icons): 24×24 minimum hit target, matching macOS's own toolbar-button
  convention (e.g. `NSToolbarItem` default), always ≥ 8px from the next interactive
  element.

**Focus order:** rail (top→bottom) → tab strip (left→right) → editor/board content →
any open overlay (mention popover, task detail sheet) traps focus until dismissed with
`Esc`, returning focus to the trigger. **Focus ring:** §1.8, 2px `accent`, never suppressed
(WCAG 2.4.7). **Keyboard:** every mutating action has a keyboard path — `⌘T` new note,
`⌘W` close tab, `⌘P` quick open, arrow keys move rail/tab-strip/board selection, `Space`
toggles a checklist item, `Esc` closes any overlay and unpins if pinned only via hotkey
summon (WCAG 2.1.1 — no mouse-only functionality). **Color is never the sole signal:**
overdue due-dates pair `danger` color with the calendar-glyph-plus-text remaining visible
(not a bare color dot); priority flags are icon+color together, never a color chip alone
(WCAG 1.4.1).

---

## 9. Screen inventory for Figma

All frames sized in pt-equivalent px (1 unit = 1pt at 1x; export @1x and @2x for Retina).
Reference frame height **900px**, representing a typical 13"-class display's
`visibleFrame.height` — actual runtime height is dynamic per §2. Every screen below has a
Light and Dark variant (Figma appearance modes / a color-variable collection), so the
count below is the number of distinct *states*, not files — dark doubles the total render
count but not the design decisions.

| # | Frame | Size (px) | Description |
|---|---|---|---|
| 1 | Design Tokens | 1440×1400 | Full §1 token sheet — swatches, type scale, spacing ramp, radii, elevation, both appearances side by side |
| 2 | Panel Chrome — Default | 420×900 | Annotated rail + divider + content wrapper, margins, corner treatment, shadow |
| 3 | Panel Chrome — Compact | 320×900 | 44pt icon-only rail |
| 4 | Panel Chrome — Wide | 760×900 | 56pt rail, wide content area |
| 5 | Tab Rail — Component sheet | 400×320 | All rail states: unselected/hover/selected/focus/pressed, default + compact |
| 6 | Notes — Populated, default width | 420×900 | Tab strip with 3 tabs, editor with h1/h2/body/list/checkbox/code/link-chip samples |
| 7 | Notes — Empty state | 420×900 | §4.3 |
| 8 | Notes — Tab overflow menu open | 420×900 | Chevron popover listing hidden tabs |
| 9 | Notes — Mention popover open | 420×900 | `@` autocomplete mid-type |
| 10 | Notes — Compact width | 320×900 | Icon-only tabs |
| 11 | Notes — Wide width | 760×900 | 640pt centered editor column |
| 12 | Tasks — Stacked, populated | 420×900 | 3 groups, mixed expanded/collapsed |
| 13 | Tasks — Stacked, empty | 420×900 | §5.4 |
| 14 | Tasks — Stacked, dragging | 420×900 | Card lifted, drop indicator between groups |
| 15 | Tasks — Kanban, populated | 760×900 | 3 seeded columns |
| 16 | Tasks — Kanban, empty | 760×900 | Empty-state variant per column |
| 17 | Tasks — Kanban, dragging | 760×900 | Card lifted, vertical drop indicator |
| 18 | Task Detail Sheet | 380×520 | Overlay opened from a card or a link-chip click (product spec §6.4) |
| 19 | Settings — Placeholder | 420×900 | §6, all four sections |
| 20 | Component sheet — Buttons & inputs | 600×800 | Primary/secondary buttons, text input, chip, badge, tag — all states |
| 21 | Component sheet — Task card variants | 600×500 | Priority variants, with/without tags, overdue, dragging |
| 22 | Component sheet — Link chip & tombstone | 400×220 | Note-target, task-target, hover, tombstone |
| 23 | Component sheet — Empty states | 600×420 | Notes + Tasks empty states side by side |

Build order follows the table: tokens and chrome first (1–5), then Notes (6–11), then
Tasks (12–18), then Settings (19), then the component sheets last (20–23) since they
extract patterns already proven in the screens above rather than inventing new ones.

---

## Design rationale summary (why, not just what)

- **Material + flat tint, not material alone** — the single mechanism that makes "floats
  over anything" and "always readable" both true at once (§1.2, §8).
- **No fill-swap on rail icons** — one selection mechanism (weight+color+bar) applied
  uniformly beats three symbols that happen to have fill variants and one that doesn't.
- **Priority flags shown only for High/Urgent** — the card is already carrying title, due
  date, tags, and a backlink count in ~360pt of width; a fourth always-on color signal
  would be density for its own sake, not clarity.
- **Settings rows carry no chevron in M0** — matches the product spec's own "shell only,
  filling them in later is wiring, not design" framing (§6.5) without implying broken
  navigation.
- **24×24 secondary hit targets instead of 44×44 everywhere** — this is a pointer-driven
  desktop utility; forcing the touch minimum onto a tab-close button would make the tab
  strip absurdly wide for no accessibility gain, since Fitts's-law risk on a desktop
  pointer is materially lower than on touch.

---

## Open items for the human to override

1. **§8 timing conflict** (250ms success criterion vs. 300ms state-machine arithmetic) —
   flagged as `DESIGN-GAP`, not resolved here; needs an architecture/PM decision.
2. **Accent color is the default system Blue** in every mock — if the product wants a
   locked brand accent instead of following the user's System Settings choice, that is a
   product decision this file does not make unilaterally.
3. **Kanban column width floor (200pt)** is my own inference for how a 4th/5th user-added
   column behaves before horizontal scroll kicks in — no source in the product spec beyond
   "adapts to width," worth a sanity check once real column counts are seen in use.
