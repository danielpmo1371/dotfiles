// Server-side verification: click Refresh in the MID toolbar and re-read the row + totals.
const MID = top.frames[1].frames[0].frames[0];
const rb = [...MID.document.querySelectorAll('*')].filter(e => e.children.length === 0 && (e.innerText || '').trim() === 'Refresh').pop();
rb.click();
await new Promise(r => setTimeout(r, 4000));
const LV = top.frames[1].frames[0].frames[1];
const scrub = s => String(s || '').replace(/\s+/g, ' ').replace(/[^A-Za-z0-9 .\/()-]/g, '').trim();
const row = [...LV.document.querySelectorAll('tr')].find(t => /FDD SoW8/.test(t.innerText));
'ROW ' + (row ? scrub(row.innerText) : 'none') + '\nTOTALS ' + LV.document.body.innerText.split('\n').filter(l => /Total Hours|Billable Hours/.test(l)).map(scrub).join(' | ');
