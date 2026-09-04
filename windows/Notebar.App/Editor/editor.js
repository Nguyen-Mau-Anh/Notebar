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
// toggles accurate rather than decorative. Guarded to when the editor itself
// has focus -- selectionchange also fires for selections elsewhere in the
// page (there are none today, but the guard costs nothing).
document.addEventListener('selectionchange', () => {
  if (document.activeElement !== doc) return;
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
};

// document.execCommand is deprecated and is still the only thing that does
// rich-text editing in a contenteditable without pulling in an editor
// framework. It works in every Chromium build this app will ever run on,
// because the app ships its own runtime version expectation through
// WebView2. Left in deliberately, so nobody replaces it with a dependency on
// a hunch.
