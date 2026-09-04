# Windows manual checks

Behaviour that CI cannot verify — it only confirms the code compiles. Each item
here needs a human running the actual build on Windows. Later tasks append to
this file rather than starting a new one.

## Window behaviour

- [ ] The panel draws over a maximized window.
- [ ] The panel draws over a borderless-fullscreen video.
- [ ] Expanding the panel does NOT take focus from the app you were typing in.
- [ ] Clicking into the note editor DOES give it keyboard focus.
- [ ] No taskbar button and no Alt-Tab entry.
- [ ] Switching virtual desktops and back: the panel still appears on hover.
- [ ] On a 150%-scaled display the panel is the same visual size as on a 100% one.
- [ ] With the taskbar docked left or top, the panel does not sit under it.
- [ ] On a multi-monitor setup, hovering the edge of a NON-primary monitor expands the
      panel on that monitor, sized to its own work area -- not the primary monitor's.

## Panel behaviour

- [ ] Hovering the handle at the right edge expands the panel within ~300 ms.
- [ ] Moving the cursor away collapses it after ~350 ms, not instantly.
- [ ] Typing in a note, then moving the cursor off the panel: it does NOT collapse.
- [ ] Pinning, then moving away: it does NOT collapse.
- [ ] Dragging a task card off the panel edge: it does NOT collapse mid-drag.
- [ ] Escape collapses it even while pinned.

## Tray and hotkey

- [ ] A Notebar icon appears in the tray (check the overflow if not visible).
- [ ] Left-clicking it toggles the panel.
- [ ] Right-clicking shows Show / Settings / Quit.
- [ ] Ctrl+Shift+N toggles the panel from any application.
- [ ] Quitting from the tray closes the app and removes the tray icon.
- [ ] Quitting from Settings does the same.
- [ ] Type in a note, quit immediately: reopening shows the typed text.
- [ ] The tray menu dismisses when you click somewhere else.
- [ ] Restart Explorer (Task Manager → Windows Explorer → Restart): the tray icon comes back.

## Chrome

- [ ] Clicking a rail tab (Notes/Tasks/Settings) switches on the FIRST click, every time --
      not just when the cursor happens to land exactly on the glyph.
- [ ] Clicking the pin toggle reflects its new state (filled icon, tinted background) on the
      FIRST click -- not one click behind.
- [ ] With the panel pinned, moving the cursor off the panel does NOT collapse it.
- [ ] With the panel pinned, the `»` collapse button in the rail still collapses it.
- [ ] Clicking `»` collapses the panel without the cursor ever leaving the panel bounds.
- [ ] Clicking Maximize resizes the panel to the half-screen column immediately -- not only
      after the next cursor movement.
- [ ] Clicking Maximize again restores the 340pt-wide card immediately, same check.
- [ ] Collapsing the panel while on the Tasks tab, then hovering the edge again: the
      collapsed handle showed the Tasks icon while collapsed, and it does not flash to some
      other icon on re-expand.
- [ ] Switching tabs while the panel is collapsed-then-reopened still shows the last
      selected tab's content, and the handle's icon matches it.
- [ ] Switch Windows to dark mode (Settings > Personalization > Colors) while the panel is
      open: rail, toolbar, and body text all switch colour immediately, with no restart and
      no element left showing the light-mode colour.
- [ ] Switch back to light mode: same check, live, no stale dark-mode colour anywhere.
- [ ] Narrow the panel below ~340pt (or use the compact/kiosk display case if available):
      the rail narrows to icon-only, no labels are half-clipped.
- [ ] Hovering an unselected rail tab, a toolbar `+`/chevron button, or the pin/maximize
      toggles shows a visible hover highlight and the glyph steps to the accent colour.
- [ ] Tab/Shift+Tab through the rail and toolbar with the keyboard: every button gets a
      visible focus ring and Enter/Space activates it.

## Editor

- [ ] Typing in a note persists after collapsing and re-expanding.
- [ ] Typing in a note persists after quitting and relaunching.
- [ ] The panel does not collapse while the cursor is outside it and you are typing.
- [ ] Clicking away from the editor, waiting 3 s, then moving the cursor off: it collapses.
- [ ] Bold, italic, H1, H2, bullets, numbers, and checklists all apply.
- [ ] A numbered list shows "1." on the first, empty line.
- [ ] Checkboxes toggle by clicking them, and the state survives a reload.
- [ ] Pasting a screenshot inserts it and it survives a relaunch.
- [ ] Right-clicking in the editor does NOT show the browser context menu.
- [ ] F12 does NOT open developer tools.
- [ ] A pasted external link opens in the default browser, not inside the panel.

## Notes tab

- [ ] Clicking a tab switches to it on the first click, every time.
- [ ] Every tab's close (x) sits on the LEFT of the title, not the right.
- [ ] Hovering an inactive tab shows its close button; moving off hides it again unless that
      tab is active (the active tab's close button stays visible either way).
- [ ] Typing in a note's body does NOT change its tab's title.
- [ ] Double-clicking a tab's title opens an inline rename field, pre-filled with the current
      title.
- [ ] Renaming a tab to something new updates the tab label immediately.
- [ ] Renaming a tab to blank (clear the field, press Enter, or click away) reverts to the
      previous title -- it never leaves an empty tab label.
- [ ] Pressing Escape while renaming cancels without changing the title.
- [ ] Closing a brand-new, still-untitled, still-empty tab deletes the note -- reopening the
      all-notes menu does not show it.
- [ ] Closing a tab that has a title, or body text, or both, KEEPS the note -- it still shows
      in the all-notes menu afterward, and reopening it from there shows the same content.
- [ ] Typing into a new note and closing its tab within a second or two (before the 400ms
      autosave would obviously have settled) still keeps the note -- it must not be deleted
      as if it were still empty.
- [ ] Clicking the chevron/all-notes button opens a menu listing every note, not only open
      ones, most recently updated first.
- [ ] A note that already has an open tab shows a small accent dot next to its title in that
      menu.
- [ ] While the all-notes menu is open, moving the cursor off the panel does NOT collapse it.
- [ ] Clicking a row in the all-notes menu opens that note (creating a tab for it if it did
      not have one) and closes the menu.
- [ ] Clicking away from the all-notes menu closes it, and the panel becomes collapsible
      again afterward (it does not get stuck open).
- [ ] Pressing Escape while the all-notes menu is open closes it the same way.
- [ ] Clicking `+` creates a new untitled note tab, makes it active, and gives the editor
      focus immediately so typing starts right away.
- [ ] Open tabs (which ones, their order, and which is active) survive collapsing and
      re-expanding the panel.
- [ ] Open tabs survive quitting and relaunching the app -- the same tabs reopen in the same
      order, with the same one active.
- [ ] Switching tabs flushes the previous note's typing -- switch away immediately after
      typing, then switch back: the text is there.
- [ ] Collapsing the panel immediately after typing, then re-expanding: the text is there.
- [ ] Type in a note and quit immediately (tray menu Quit, not just closing/collapsing): on
      relaunch, the typed text is present -- it must not be lost to a save that lost the race
      with the app exiting.

## Formatting

- [ ] Each of the eight formatting-bar buttons (Bold, Italic, Code, H1, H2, Bulleted list,
      Numbered list, Checklist) applies its formatting when clicked.
- [ ] Every formatting-bar button shows its intended mark -- none renders as a blank
      space or an empty box. (The macOS build shipped six invisible glyphs this way.)
- [ ] Making a paragraph an H1, then clicking H1 again, returns it to normal text.
      Same for H2 and Code. (Chromium's formatBlock does not toggle by itself.)
- [ ] Placing the caret inside bold/italic/code/H1/H2/bulleted/numbered/checklist text lights
      up the matching button, and moving the caret out of it turns the button back off --
      the toggle state tracks the caret live, it is not a fixed decoration.
- [ ] Selecting a run of text that mixes styles (e.g. partly bold) shows the expected
      queryCommandState result rather than a stale or frozen state from the previous
      selection.
- [ ] A brand-new numbered list shows "1." on its first line while that line is still empty
      -- nothing needs to be typed first.
- [ ] Clicking a checkbox toggles it; clicking the checklist item's text does not. The
      checked look survives closing and reopening the note (collapse/re-expand and
      quit/relaunch both).
- [ ] Typing `- ` at the start of an empty line converts it into a bulleted list item, and
      the trigger text itself does not remain in the document.
- [ ] Typing `1. ` at the start of an empty line converts it into a numbered list item.
- [ ] Typing `[] ` at the start of an empty line converts it into a checklist item with a
      real, clickable checkbox.
- [ ] Typing `# ` at the start of an empty line converts it into an H1; `## ` converts it
      into an H2.
- [ ] Typing `- `/`1. `/`[] `/`# ` inside a code block (a `<pre>`) does NOT trigger the
      shortcut -- the characters and the space stay as literal text.
- [ ] Pasting a screenshot inserts it inline, and it is still there after collapsing and
      re-expanding, and after quitting and relaunching the app.
- [ ] Pasting a very large screenshot (longer edge well above 2000px) still inserts
      successfully and is visibly smaller than the original when reopened -- confirms the
      downscale path ran rather than storing the image at full size.
- [ ] Deleting an image from a note's body (select it, press Delete) and then waiting past
      the 400ms autosave: the note no longer shows the image, and its attachment row is
      eventually removed by `IAttachmentRepository.DeleteUnreferenced` (not directly
      observable in the UI, but a note re-opened after this should not reference a
      dangling asset id, and the app should not error loading it).

## Tasks board

- [ ] Dragging a card from Queue to Working moves it; dragging Working to Done moves it;
      dragging Done back to Queue or Working moves it -- every pairwise combination of the
      three columns, not just adjacent ones.
- [ ] Dropping a card into an EMPTY column (drag the last card out of Working, then drag a
      different card back in) succeeds -- the empty column is a real drop target, not just
      its header row.
- [ ] Starting a drag and, mid-drag, checking that the panel does not collapse even if the
      cursor briefly leaves the panel bounds while still holding the mouse button.
- [ ] Dragging a card off the panel's edge and releasing there: the drag cancels (the card
      stays in its original column/position) rather than the panel collapsing out from under
      it.
- [ ] Clicking `+` creates a new task in Queue, opens straight into its detail pane, and the
      title field is already focused -- typing immediately replaces "New Task" with no extra
      click needed to start editing.
- [ ] Opening a card's detail pane, then clicking a different card without clicking Back
      first: the pane updates in place to the new task -- the board does not need to be
      revisited between the two.
- [ ] Clicking Back from the detail pane returns to the board, and clicking the same card
      again reopens its detail pane (selection was cleared, not left stuck).
- [ ] Dragging a card into Done stamps a Completed time (visible in its detail pane's meta
      line); dragging it back out to Queue or Working clears that Completed time.
- [ ] Reordering a card within Done (drag it above or below another Done card, without
      leaving the column) does NOT change its Completed time -- only entering/leaving Done
      does.
- [ ] Editing a task's priority or due date from its detail pane's flyouts, then opening a
      DIFFERENT task's detail pane and switching back: the first task's edits are still
      there (not reverted or overwritten by the second task's data).
- [ ] Deleting a task from its open detail pane returns to the board with the card gone and
      the column counts updated.
- [ ] Column count badges (next to Queue/Working/Done) match the actual number of cards
      after every create, delete, and drag.
- [ ] The board's empty state ("No tasks yet") shows only when all three columns are empty,
      and disappears the moment the first task is created.
- [ ] Rename a task in the detail pane, go back -- the card on the board shows the new name
      immediately, without needing to reopen the detail pane to confirm the rename stuck.
- [ ] Change a task's priority in the detail pane, go back -- the card's flag (or lack of
      one) on the board reflects the new priority immediately.
- [ ] Drag a card with a past due date into Done, then drag it back out -- the card's
      due-date styling updates (stops, then resumes, showing overdue-red) on the board
      itself, without opening its detail pane.
- [ ] Start dragging a card -- the detail pane does not flash open as the drag begins.

## Linking

- [ ] Typing `@` in a note opens the mention popover; typing more characters filters it to
      matching notes and tasks.
- [ ] While the mention popover is open, the panel does NOT collapse even if the cursor
      leaves the panel bounds or the note editor loses keyboard focus (e.g. clicking a
      candidate row in the popover itself).
- [ ] Pressing Escape while the popover is open closes it, the trigger `@` and any typed
      query stay as plain text, and the panel collapses normally afterward (hovering away
      no longer keeps it pinned open).
- [ ] Clicking outside both the note editor and the popover (e.g. the tab strip) closes the
      popover via click-away, and the panel collapses normally afterward.
- [ ] ArrowUp/ArrowDown move the popover's highlighted row without moving the caret in the
      note; Enter and Tab both insert the highlighted candidate as a chip.
- [ ] Selecting a note from the popover inserts a chip at the `@query` position, replacing
      the typed text entirely (no leftover `@` or query characters).
- [ ] After inserting a chip, collapsing/re-expanding the panel and quitting/relaunching the
      app both show the chip still in place and still clickable.
- [ ] Clicking a note chip opens that note as a tab (creating one if it doesn't already have
      one) and switches to it.
- [ ] Clicking a task chip in a note switches to the Tasks board, selects that task, and
      opens its detail pane.
- [ ] Clicking a task chip whose target was deleted since the chip was written does nothing
      harmful (no crash, no error) -- it does not switch tabs or open an empty/broken detail
      pane.
- [ ] A note that other notes/tasks link to shows a "Backlinks" section below its editor,
      listing each of them; a note with no backlinks shows no such section at all.
- [ ] Clicking a note row in the backlinks list opens that note as a tab, the same as
      clicking a chip pointing at it would.
- [ ] Deleting a note that another note links to: reopening the note holding the chip shows
      it struck through (tombstoned) instead of in its normal chip styling.
- [ ] Clicking a tombstoned chip does nothing -- no navigation, no error.
- [ ] Restoring the situation (create a new note, link to it, confirm the chip renders
      normally, not tombstoned) after a tombstone check, to confirm tombstoning is specific
      to the deleted target and not stuck on for the whole session.

## Settings

- [ ] General -> Theme: choosing Light/Dark/System changes the panel's own colours
      immediately, with the panel still open -- no relaunch, no flicker of the old colours
      anywhere in the rail, toolbar, or Settings tab itself.
- [ ] Restarting the app after choosing Light or Dark opens directly into that appearance,
      not System.
- [ ] Activation's three sliders (Open delay, Close delay, Edge tolerance) show the
      currently-saved values on open, not defaults, if a non-default value was set in an
      earlier session.
- [ ] Dragging a slider updates its own value label live as it moves.
- [ ] After changing a slider, hovering the edge (or moving away) uses the NEW timing on the
      very next dwell -- not the old one, and not only after a relaunch.
- [ ] Restarting the app after changing a slider opens with that same value still set.
- [ ] Data -> Location shows the real on-disk path (not a placeholder), and "Reveal in File
      Explorer" opens File Explorer with notebar.sqlite pre-selected.
- [ ] Data -> Size on disk shows a plausible, non-zero value once at least one note exists,
      and increases after writing a substantial amount of new text.
- [ ] Data -> Applied migrations lists at least one migration name, not "none", on a normal
      install.
- [ ] **The in-memory warning is genuinely unmissable.** Force the on-disk database to fail
      to open (e.g. make `%LOCALAPPDATA%\Notebar\notebar.sqlite` read-only or point
      `%LOCALAPPDATA%` somewhere without write access before launch), then open Settings ->
      Data: the warning row is the first thing seen in the Data section, not something you
      have to scroll to or notice among other fields, and Location's Reveal button is
      disabled rather than pointing at nothing.
- [ ] With a normal, writable on-disk database, the in-memory warning row does NOT appear at
      all.
- [ ] Export Diagnostics opens a real Save dialog; the saved .txt file contains the app
      version, Windows version, database facts, and a log section -- and, if any notes or
      tasks exist with distinctive text in their titles/bodies, that text does NOT appear
      anywhere in the exported file.
- [ ] About -> Version shows a real version string (e.g. "0.1.0 (0)"), not "unknown".
- [ ] About -> Quit Notebar closes the app and removes the tray icon, the same as quitting
      from the tray menu.
- [ ] The Quit button's red styling is visible and reads as destructive in both light and
      dark mode (its hover/pressed state was never seen rendered -- only its resting
      Background/Foreground were set explicitly, so WinUI's default pointer-over/pressed
      visual states may not carry the same red tint).
- [ ] Switching to the Settings tab, doing something elsewhere that changes the database
      (e.g. writing a note), then switching back to Settings without leaving the app: Size on
      disk reflects the change rather than showing a stale number from when the tab was first
      opened.

## Release artifacts

- [ ] Any .msix attached to a release actually contains Notebar.App.exe
      (`unzip -l` it). 0.1.0 shipped the Windows App SDK's own framework package
      under our filename because a bare *.msix glob matched it.
