// Commit and close the Enter Notes dialog (needs the pointer/mouse sequence on .Button2).
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const txt = e => (e.innerText || e.textContent || '').trim();
const find = () => [...d.querySelectorAll('body *')].find(e => /Dialog/i.test(e.className) && e.offsetWidth > 200 && e.offsetHeight > 100 && /Enter Notes/i.test(txt(e)));
const leaf = [...find().querySelectorAll('*')].filter(e => e.children.length === 0 && txt(e) === 'OK').pop();
const btn = leaf.closest('.Button2') || leaf.parentElement;
['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(t => { const Ev = t.startsWith('pointer') ? w.PointerEvent : w.MouseEvent;
  btn.dispatchEvent(new Ev(t, { bubbles: true, cancelable: true, button: 0, view: w })); });
await new Promise(r => setTimeout(r, 1500));
const labels = [...d.querySelectorAll('body *')].filter(e => e.children.length === 0 && /^(Sun|Mon|Tue|Wed|Thu|Fri|Sat) \d\d\/\d\d$/.test(txt(e)));
const boxes = [...d.querySelectorAll('input.DecimalBox2')];
const days = labels.map(l => { const lr = l.getBoundingClientRect(); const b = boxes.filter(i => { const r = i.getBoundingClientRect();
  return r.top > lr.bottom - 2 && Math.abs((r.left + r.width / 2) - (lr.left + lr.width / 2)) < 40 && r.width > 0; })[0]; return txt(l) + ':' + (b && b.value || '-'); });
'dialogOpen ' + !!find() + ' days ' + days.join(' ');
