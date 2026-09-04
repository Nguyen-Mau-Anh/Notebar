// The guest half of the host/editor bridge. One typed message envelope in
// each direction, never ad-hoc strings — see Notebar.App/Editor/EditorBridge.cs
// for the host side that parses what post() sends and drives window.notebar.

// Guest → host. Every message is {type, ...}; the host switches on type.
function post(message) {
  window.chrome.webview.postMessage(JSON.stringify(message));
}

const doc = document.getElementById('doc');

// The two facts the panel's collapse policy depends on. Focus is reported on
// both edges, and the host also polls it — see the host side for why relying on
// events alone was the bug that left the macOS panel permanently open.
doc.addEventListener('focus', () => post({ type: 'focus', focused: true }));
doc.addEventListener('blur',  () => post({ type: 'focus', focused: false }));
doc.addEventListener('keydown', () => post({ type: 'keystroke' }));

// Debounced content change. 400 ms matches the macOS editor's save debounce.
let saveTimer = null;
doc.addEventListener('input', () => {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => post({ type: 'change', html: doc.innerHTML }), 400);
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
    post({ type: 'change', html: doc.innerHTML });
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

// Host → guest.
window.notebar = {
  setContent(html)      { doc.innerHTML = html; },
  getContent()          { return doc.innerHTML; },
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
