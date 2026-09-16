// In the New Task Time Entry popup: open the Enter Notes dialog for DAY_LABEL (e.g. 'Mon 14/09').
const DAY_LABEL = 'DAY_LABEL_HERE'; // ddd dd/MM of the target date, e.g. 'Mon 14/09'
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const txt = e => (e.innerText || e.textContent || '').trim();
const all = [...d.querySelectorAll('body *')];
const label = all.find(e => e.children.length === 0 && txt(e) === DAY_LABEL);
const lr = label.getBoundingClientRect();
const box = [...d.querySelectorAll('input.DecimalBox2')].filter(i => { const r = i.getBoundingClientRect();
  return r.top > lr.bottom - 2 && Math.abs((r.left + r.width / 2) - (lr.left + lr.width / 2)) < 40 && r.width > 0; })
  .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)[0];
const mr = box.getBoundingClientRect();
const noteBtn = all.find(e => /ButtonIcon/.test(e.className) && /Note/.test(e.className) && (() => {
  const r = e.getBoundingClientRect(); return r.top >= mr.bottom - 5 && r.top < mr.bottom + 40 && Math.abs(r.left - mr.left) < 50; })());
noteBtn.click();
await new Promise(r => setTimeout(r, 1500));
const dlg = [...d.querySelectorAll('body *')].find(e => /Dialog/i.test(e.className) && e.offsetWidth > 200 && e.offsetHeight > 100 && /Enter Notes/i.test(txt(e)));
'dialog ' + (dlg ? txt(dlg).split('\n')[0].replace(/[^A-Za-z0-9 \/-]/g, '') : 'NOT OPEN') + ' existingHours ' + (dlg ? dlg.querySelector('input.DecimalBox2').value : '');
