// Commit the current day and move the dialog to the next date.
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const txt = e => (e.innerText || e.textContent || '').trim();
const find = () => [...d.querySelectorAll('body *')].find(e => /Dialog/i.test(e.className) && e.offsetWidth > 200 && e.offsetHeight > 100 && /Enter Notes/i.test(txt(e)));
const leaf = [...find().querySelectorAll('*')].filter(e => e.children.length <= 1 && txt(e) === 'Next Day').pop();
leaf.click();
await new Promise(r => setTimeout(r, 1500));
'now ' + txt(find()).split('\n')[0].replace(/[^A-Za-z0-9 \/-]/g, '');
