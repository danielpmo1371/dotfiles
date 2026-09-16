// Duplicates 30 + 33 on purpose so the read-back is one self-contained call.
// Re-open each listed day's Notes dialog and read back hours + summary, closing with OK.
const DAYS = []; // DAY_LABELs entered this run, e.g. ['Mon 14/09', 'Tue 15/09']
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const txt = e => (e.innerText || e.textContent || '').trim();
const find = () => [...d.querySelectorAll('body *')].find(e => /Dialog/i.test(e.className) && e.offsetWidth > 200 && e.offsetHeight > 100 && /Enter Notes/i.test(txt(e)));
const out = [];
for (const DAY_LABEL of DAYS) {
  const all = [...d.querySelectorAll('body *')];
  const label = all.find(e => e.children.length === 0 && txt(e) === DAY_LABEL); const lr = label.getBoundingClientRect();
  const box = [...d.querySelectorAll('input.DecimalBox2')].filter(i => { const r = i.getBoundingClientRect();
    return r.top > lr.bottom - 2 && Math.abs((r.left + r.width / 2) - (lr.left + lr.width / 2)) < 40 && r.width > 0; })[0];
  const mr = box.getBoundingClientRect();
  const nb = all.find(e => /ButtonIcon/.test(e.className) && /Note/.test(e.className) && (() => { const r = e.getBoundingClientRect();
    return r.top >= mr.bottom - 5 && r.top < mr.bottom + 40 && Math.abs(r.left - mr.left) < 50; })());
  nb.click(); await new Promise(r => setTimeout(r, 1200));
  const dlg = find(); const eds = [...dlg.querySelectorAll('.ContentEditable2')].filter(e => e.isContentEditable);
  out.push(txt(dlg).split('\n')[0].replace(/[^A-Za-z0-9 \/-]/g, '') + ' hours ' + dlg.querySelector('input.DecimalBox2').value + ' summary[' + txt(eds[0]).slice(0, 40).replace(/[^A-Za-z0-9 ]/g, '') + '] len ' + txt(eds[0]).length);
  const leaf = [...dlg.querySelectorAll('*')].filter(e => e.children.length === 0 && txt(e) === 'OK').pop(); const btn = leaf.closest('.Button2') || leaf.parentElement;
  ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(t => { const Ev = t.startsWith('pointer') ? w.PointerEvent : w.MouseEvent;
    btn.dispatchEvent(new Ev(t, { bubbles: true, cancelable: true, button: 0, view: w })); });
  await new Promise(r => setTimeout(r, 1200));
}
out.join('\n') + '\ndialogOpen ' + !!find();
