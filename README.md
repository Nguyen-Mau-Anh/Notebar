# Notebar

An always-available scratch surface docked to the right edge of the screen. Invisible
until your cursor reaches the edge, then it slides out over whatever you're working in —
including fullscreen apps.

- **Notes** — multiple notes as tabs, Notepad++ style, rich text.
- **Tasks** — a board with statuses; drag cards between them to trace work.
- **Links** — notes and tasks reference each other, with backlinks.

macOS first; Windows via a single platform-adapter module.

## Status

Planning. See [`docs/superpowers/specs/2026-08-29-notebar-design.md`](docs/superpowers/specs/2026-08-29-notebar-design.md)
for the design spec.

## Stack

Electron · React 19 · TypeScript · TipTap · dnd-kit · SQLite (better-sqlite3 + Drizzle) · Tailwind

## Milestones

| | Scope |
|---|---|
| M0 | Panel shell — window, hot edge, state machine, tab rail |
| M1 | Notes — schema, editor, tabs, search |
| M2 | Tasks — board, drag, ordering |
| M3 | Linking — mentions, chips, backlinks |
| M4 | Settings and polish |
| M5 | Windows |
