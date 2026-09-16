// Read the timesheet grid: MBIE row per-day hours and the totals. Safe output (no URLs).
const LV = top.frames[1].frames[0].frames[1];
const row = [...LV.document.querySelectorAll('tr')].find(t => /FDD SoW8/.test(t.innerText));
const scrub = s => String(s || '').replace(/\s+/g, ' ').replace(/[^A-Za-z0-9 .\/()-]/g, '').trim();
const hdr = [...LV.document.querySelectorAll('tr')].find(t => /Client \/ Project/.test(t.innerText));
'HEADER ' + scrub(hdr && hdr.innerText) + '\nROW ' + (row ? scrub(row.innerText) : 'NONE - run Get Previous Tasks') +
'\nTOTALS ' + LV.document.body.innerText.split('\n').filter(l => /Total Hours|Billable Hours/.test(l)).map(l => scrub(l)).join(' | ');
