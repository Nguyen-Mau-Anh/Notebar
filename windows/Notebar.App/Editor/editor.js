// The guest half of the host/editor bridge. One typed message envelope in
// each direction, never ad-hoc strings — see Notebar.App/Editor/EditorBridge.cs
// for the host side that parses what post() sends and drives window.notebar.

// Guest → host. Every message is {type, ...}; the host switches on type.
// Every message also carries the document generation it was produced
// against (see setContent below) — the host drops anything whose
// generation does not match the note it currently thinks is loaded. That
// is the backstop for a debounced save that was still in flight, against
// the note being switched away from, when the switch happened: cancelling
// the timer in setContent narrows the window, this closes it. Without it, a
// stale save can land on the wrong note and, via DeleteUnreferenced, delete
// every image the new note actually references.
let docGeneration = 0;
function post(message) {
  window.chrome.webview.postMessage(JSON.stringify({ ...message, generation: docGeneration }));
}

const doc = document.getElementById('doc');

// The two facts the panel's collapse policy depends on. Focus is reported on
// both edges, and the host also polls it — see the host side for why relying on
// events alone was the bug that left the macOS panel permanently open.
doc.addEventListener('focus', () => post({ type: 'focus', focused: true }));
doc.addEventListener('blur',  () => post({ type: 'focus', focused: false }));
doc.addEventListener('keydown', () => post({ type: 'keystroke' }));

// The html actually captured for a save: a clone with tombstone styling
// stripped. markTombstones toggles that class on the live DOM, and this
// same DOM's innerHTML is what a save would otherwise capture verbatim —
// tombstone-ness is derived from which link targets still exist and must
// never round-trip through storage, the same rule that keeps color out of
// stored content.
function contentForSave() {
  const clone = doc.cloneNode(true);
  clone.querySelectorAll('a.tombstone').forEach(a => a.classList.remove('tombstone'));
  return clone.innerHTML;
}

// Debounced content change. 400 ms matches the macOS editor's save debounce.
let saveTimer = null;
doc.addEventListener('input', () => {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => post({ type: 'change', html: contentForSave() }), 400);
});

// A link chip is a navigation the host handles, never one the WebView performs.
doc.addEventListener('click', (e) => {
  const anchor = e.target.closest('a[href^="notebar://"]');
  if (!anchor) return;
  e.preventDefault();
  post({ type: 'chip', url: anchor.getAttribute('href') });
});

// Checkbox toggles are a DOM event, not hit-testing against a glyph. On macOS
// this needed a click-region calculation per checkbox and a font-availability
// check, because the obvious glyph rendered as nothing in the system font.
doc.addEventListener('change', (e) => {
  if (e.target.matches('input[type="checkbox"]')) {
    e.target.toggleAttribute('checked', e.target.checked);
    post({ type: 'change', html: contentForSave() });
  }
});

// Pasted images go to the host as a data URL; the host stores the bytes as an
// attachment row and replies with the asset URL to substitute in.
doc.addEventListener('paste', (e) => {
  const item = [...e.clipboardData.items].find(i => i.type.startsWith('image/'));
  if (!item) return;
  e.preventDefault();
  const reader = new FileReader();
  reader.onload = () => post({ type: 'image', dataUrl: reader.result });
  reader.readAsDataURL(item.getAsFile());
});

// The exact snippet FormattingBar.ChecklistHtml (C#) builds for its own
// checklist button. Kept in sync by comment on both sides of the bridge,
// since a literal can't be shared across the language boundary the way
// docGeneration's stamping logic can.
const CHECKLIST_HTML = '<ul class="checklist"><li><input type="checkbox"> </li></ul>';

// Markdown shortcuts (Task 13, spec deliverable 3 ported to the browser):
// "- " starts a bullet, "1. " (any digits) a numbered item, "[] " a
// checklist item, "# "/"## " a heading. Unlike the macOS build
// (NoteMarkdownShortcuts.swift), nothing here synthesises a list marker as
// text -- the browser draws <ol>/<ul> markers natively, including on an
// empty first line, which is the whole reason that requirement exists (see
// editor.css's own remarks on #doc ul/ol).
const numberedMarkerPattern = /^[0-9]+\.$/;

// Block-level containers a shortcut can trigger from. #doc itself covers the
// loose first line of a fresh document, which has no wrapping element yet.
const lineBlockTags = new Set(['P', 'DIV', 'LI', 'H1', 'H2', 'BLOCKQUOTE']);

function elementAt(node) {
  return node && node.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement ?? null;
}

// The text from the start of the caret's own line up to the caret itself --
// exactly the range a markdown marker like "- " or "1. " would occupy, and
// the same range the keydown listener below deletes once it recognizes one.
function lineRangeBeforeCaret(caretRange) {
  let el = elementAt(caretRange.startContainer);
  while (el && el !== doc && !lineBlockTags.has(el.tagName)) el = el.parentElement;
  const range = document.createRange();
  range.setStart(el ?? doc, 0);
  range.setEnd(caretRange.startContainer, caretRange.startOffset);
  return range;
}

doc.addEventListener('keydown', (e) => {
  if (e.key !== ' ') return;
  const sel = window.getSelection();
  if (!sel || !sel.isCollapsed || sel.rangeCount === 0) return;
  const caretRange = sel.getRangeAt(0);
  if (!doc.contains(caretRange.startContainer)) return;
  // "- " typed deliberately inside a code block must stay literal text, not
  // become a list.
  if (elementAt(caretRange.startContainer)?.closest('pre')) return;

  const lineRange = lineRangeBeforeCaret(caretRange);
  const marker = lineRange.toString();

  let command = null;
  let value = null;
  let isChecklist = false;
  if (marker === '-') {
    command = 'insertUnorderedList';
  } else if (numberedMarkerPattern.test(marker)) {
    command = 'insertOrderedList';
  } else if (marker === '[]') {
    isChecklist = true;
  } else if (marker === '#') {
    command = 'formatBlock';
    value = '<h1>';
  } else if (marker === '##') {
    command = 'formatBlock';
    value = '<h2>';
  } else {
    return;
  }

  // Consume the space that triggered this rather than inserting it and
  // undoing it -- the marker text is deleted through execCommand('delete'),
  // not a raw Range mutation, so it goes through the same editing pipeline
  // as everything else and posts the usual "input" event the 400ms save
  // debounce (above) already listens for.
  e.preventDefault();
  sel.removeAllRanges();
  sel.addRange(lineRange);
  document.execCommand('delete', false);
  document.execCommand(isChecklist ? 'insertHTML' : command, false, isChecklist ? CHECKLIST_HTML : value);
});

// Button state reflects the selection (Task 13): the host cannot poll the
// guest's DOM itself, so the guest polls document.queryCommandState/Value on
// every selectionchange and posts the result, keeping FormattingBar's
// toggles accurate rather than decorative.
function postStyles() {
  const sel = window.getSelection();
  const el = sel && sel.rangeCount > 0 ? elementAt(sel.getRangeAt(0).startContainer) : null;
  const inChecklist = !!el?.closest('#doc ul.checklist');
  const blockTag = (document.queryCommandValue('formatBlock') || '').toLowerCase();

  post({
    type: 'styles',
    bold: document.queryCommandState('bold'),
    italic: document.queryCommandState('italic'),
    code: blockTag === 'pre',
    heading1: blockTag === 'h1',
    heading2: blockTag === 'h2',
    // A checklist <ul> still reads as an "unordered list" to execCommand, so
    // bulletedList is explicitly false while inside one -- otherwise both
    // buttons would light up together.
    bulletedList: document.queryCommandState('insertUnorderedList') && !inChecklist,
    numberedList: document.queryCommandState('insertOrderedList'),
    checklist: inChecklist,
  });
}

// selectionchange fires on every intermediate selection during a drag -- one
// message per frame is as often as the toolbar can visibly update anyway, and
// keeps this path as traffic-conscious as the 400ms save debounce above.
// activeElement is checked at schedule time, not just inside postStyles:
// a selection change elsewhere on the page (there is nowhere else today, but
// the guard costs nothing) should not even queue a frame.
let stylesFrame = 0;
document.addEventListener('selectionchange', () => {
  if (document.activeElement !== doc) return;
  if (stylesFrame) return;
  stylesFrame = requestAnimationFrame(() => {
    stylesFrame = 0;
    postStyles();
  });
});

// --- @ mention autocomplete (Task 15, product spec §6.4 deliverable 3) ---
//
// Mirrors macOS's NoteMentionContext.refresh(): detects an "@" typed
// immediately before the caret, tracks the query typed since, and ends the
// session the same three ways -- whitespace/newline appearing in the query,
// the caret moving to before the "@", or (implicitly, via mentionAnchor
// staying valid only while the caret is still ahead of it) any edit that
// invalidates the range between the two. The popover itself is host-side
// XAML (NoteEditorHost.MentionUpdated / NotesTab), never built here -- this
// side only detects the session and reports it, exactly the same split
// AllNotesMenu already has between "renders rows" and "owns the Flyout".
//
// mentionAnchor is a live DOM Range endpoint {node, offset} pointing at the
// "@" character itself, not an index into a string -- contenteditable
// mutates the same Text node as the user keeps typing, so this offset never
// needs to be recomputed as the query grows.
let mentionAnchor = null;

// The caret's own client-coordinate rect, for the host to anchor the
// popover below (screen spec §4.2: "anchored below the text-insertion
// point"). A collapsed Range usually reports a real client rect; the one
// case it doesn't in Chromium is a caret at the very start of an empty
// line, where this falls back to the containing block element's own rect.
function caretRect() {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return null;
  const range = sel.getRangeAt(0).cloneRange();
  range.collapse(true);
  const rects = range.getClientRects();
  if (rects.length > 0) return rects[0];
  const el = elementAt(range.startContainer);
  return el ? el.getBoundingClientRect() : null;
}

// The text between mentionAnchor (just after the "@") and the caret -- the
// live query. Range.setEnd throws if the caret has moved to before
// mentionAnchor (DOM Ranges require start <= end in document order); that
// throw is exactly the "caret moved in front of the @" cancellation signal,
// so it is caught rather than left to propagate.
function mentionQuery(caretRange) {
  if (!mentionAnchor) return null;
  const probe = document.createRange();
  probe.setStart(mentionAnchor.node, mentionAnchor.offset);
  try {
    probe.setEnd(caretRange.startContainer, caretRange.startOffset);
    return probe.toString();
  } catch {
    return null;
  }
}

function postMention(open, query) {
  const rect = open ? caretRect() : null;
  post({
    type: 'mention',
    open,
    query,
    x: rect ? rect.left : 0,
    y: rect ? rect.bottom : 0,
  });
}

// Ends the session without inserting anything and tells the host to close
// whatever popover it has showing. A no-op if no session is active, so
// callers on a teardown path (setContent below) can call this
// unconditionally.
function cancelMention() {
  if (!mentionAnchor) return;
  mentionAnchor = null;
  post({ type: 'mention', open: false, query: '', x: 0, y: 0 });
}

// Called on every text change and every selection change while the
// document has focus (see the two listeners below) -- detects the start of
// a new session and, for an already-active one, re-filters on the text
// typed since, or ends it per mentionQuery's own rules above.
function refreshMention() {
  const sel = window.getSelection();
  if (!sel || !sel.isCollapsed || sel.rangeCount === 0) { cancelMention(); return; }
  const caretRange = sel.getRangeAt(0);
  if (!doc.contains(caretRange.startContainer)) { cancelMention(); return; }

  if (mentionAnchor) {
    const query = mentionQuery(caretRange);
    if (query === null || /\s/.test(query) || query.includes('@')) {
      cancelMention();
      return;
    }
    postMention(true, query);
    return;
  }

  // Look at the character immediately before the caret for a freshly typed
  // "@". Only a text-node caret can have a character "immediately before
  // it" in the sense this needs.
  const node = caretRange.startContainer;
  const offset = caretRange.startOffset;
  if (node.nodeType !== Node.TEXT_NODE || offset === 0) return;
  if (node.textContent[offset - 1] !== '@') return;

  mentionAnchor = { node, offset: offset - 1 };
  postMention(true, '');
}

doc.addEventListener('input', refreshMention);
document.addEventListener('selectionchange', () => {
  if (document.activeElement !== doc) return;
  refreshMention();
});

// Escape and the three navigation keys the host-side popover needs are
// intercepted here with preventDefault -- without it Escape does nothing
// AppKit-visible, ArrowUp/ArrowDown would move the caret instead of the
// popover's selection, and Enter/Tab would insert a newline/tab character
// into the note instead of committing a candidate. Only intercepted while a
// mention session is actually active, so ordinary typing is never affected.
doc.addEventListener('keydown', (e) => {
  if (!mentionAnchor) return;
  if (e.key === 'Escape') {
    e.preventDefault();
    cancelMention();
    return;
  }
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter' || e.key === 'Tab') {
    e.preventDefault();
    post({ type: 'mentionKey', key: e.key });
  }
});

// Host → guest.
window.notebar = {
  setContent(html, generation) {
    // Replacing the document invalidates any save still waiting out its
    // debounce: it describes the note we are navigating away from, not
    // the one about to be shown.
    clearTimeout(saveTimer);
    saveTimer = null;
    docGeneration = generation;
    doc.innerHTML = html;
    // A mention session belongs to the note it started in -- mentionAnchor
    // would otherwise point at a Text node that just got torn out of the
    // document, and the popover it drove would be showing over the wrong
    // note's editor. Mirrors macOS's NoteEditorContainer building a fresh
    // NoteMentionContext per note (`.id(activeID)`); this can't rebuild the
    // whole module, so it just resets the one piece of state instead.
    cancelMention();
  },
  getContent()          { return contentForSave(); },
  hasFocus()            { return document.activeElement === doc; },
  setTheme(theme)       { document.documentElement.dataset.theme = theme; },
  exec(command, value)  { doc.focus(); document.execCommand(command, false, value ?? null); },
  insertHtml(html)      { doc.focus(); document.execCommand('insertHTML', false, html); },
  markTombstones(ids)   {
    const alive = new Set(ids);
    doc.querySelectorAll('a[href^="notebar://"]').forEach(a => {
      a.classList.toggle('tombstone', !alive.has(a.getAttribute('href')));
    });
  },
  // Task 15: replaces the "@query" text the active mention session is
  // sitting on with a chip, then hands back the resulting document html so
  // the host can save it -- NoteEditorHost.InsertChipAsync writes that html
  // and the link row together through ILinkRepository.CreateSavingNoteBody
  // rather than waiting for the ordinary 400ms debounced save, so a crash
  // between "chip is in the DOM" and "the link row exists" is impossible.
  // Selects the range from mentionAnchor to the caret's current position
  // (wherever it ended up -- always exactly the "@query" text the user
  // typed) and lets execCommand('insertHTML') replace that selection, the
  // same mechanism the markdown shortcuts above use to replace a marker.
  insertMentionChip(html) {
    doc.focus();
    const sel = window.getSelection();
    if (mentionAnchor && sel && sel.rangeCount > 0) {
      const caretRange = sel.getRangeAt(0);
      const range = document.createRange();
      range.setStart(mentionAnchor.node, mentionAnchor.offset);
      range.setEnd(caretRange.startContainer, caretRange.startOffset);
      sel.removeAllRanges();
      sel.addRange(range);
    }
    // Cleared *before* execCommand, not after -- same reasoning as macOS's
    // NoteMentionContext.select(_:): insertHTML fires a synchronous 'input'
    // event that re-enters refreshMention() before this call returns, and
    // that re-entrant call must see no active session rather than try to
    // re-derive a query against a chip's own inserted text.
    mentionAnchor = null;
    document.execCommand('insertHTML', false, html);
    return contentForSave();
  },
  // The host's answer to a mention popover closing without a row having
  // been selected (Escape already handles itself guest-side; this covers
  // the Flyout's own light-dismiss on a click outside both the document and
  // the popover, which the guest has no way to observe on its own).
  cancelMention() { mentionAnchor = null; },
};

// document.execCommand is deprecated and is still the only thing that does
// rich-text editing in a contenteditable without pulling in an editor
// framework. It works in every Chromium build this app will ever run on,
// because the app ships its own runtime version expectation through
// WebView2. Left in deliberately, so nobody replaces it with a dependency on
// a hunch.
