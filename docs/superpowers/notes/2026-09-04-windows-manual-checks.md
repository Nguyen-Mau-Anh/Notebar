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
