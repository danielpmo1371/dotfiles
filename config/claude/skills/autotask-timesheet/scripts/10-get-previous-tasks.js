// After a REAL click on "Get Previous Tasks" (hook installed first): list the popup rows.
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const scrub = s => String(s || '').replace(/\s+/g, ' ').replace(/[^A-Za-z0-9 .\/()-]/g, '').trim();
const rows = [...d.querySelectorAll('tr')].filter(t => t.querySelector('img')).map((t, i) => i + ' ' + scrub(t.innerText));
'TITLE ' + scrub(d.title) + '\n' + scrub(d.body.innerText.split('\n')[0]) + '\nROWS\n' + rows.join('\n');
