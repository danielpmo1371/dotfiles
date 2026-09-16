// Save & Close the New Task Time Entry popup, then read the reloaded grid row.
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const txt = e => (e.innerText || e.textContent || '').trim();
const leaf = [...d.querySelectorAll('body *')].filter(e => e.children.length === 0 && /^Save\s*&\s*Close$/.test(txt(e))).shift();
const btn = leaf.closest('.Button2') || leaf.parentElement;
['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(t => { const Ev = t.startsWith('pointer') ? w.PointerEvent : w.MouseEvent;
  btn.dispatchEvent(new Ev(t, { bubbles: true, cancelable: true, button: 0, view: w })); });
await new Promise(r => setTimeout(r, 4000));
let closed; try { closed = w.closed; } catch (e) { closed = 'err'; }
const LV = top.frames[1].frames[0].frames[1];
const row = [...LV.document.querySelectorAll('tr')].find(t => /FDD SoW8/.test(t.innerText));
'popupClosed ' + closed + ' row ' + (row ? row.innerText.replace(/\s+/g, ' ').replace(/[^A-Za-z0-9 .\/-]/g, '').slice(0, 200) : 'none');
