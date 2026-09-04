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
