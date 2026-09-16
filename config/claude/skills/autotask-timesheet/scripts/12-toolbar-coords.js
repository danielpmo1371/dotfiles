// Viewport coordinates of a MID toolbar button by its label (e.g. 'Get Previous Tasks', 'Refresh').
// Run twice 1.5 s apart and proceed only when the result is identical (layout settles late).
const LABEL = 'Get Previous Tasks';
const MID = top.frames[1].frames[0].frames[0];
const leaf = [...MID.document.querySelectorAll('*')].filter(e => e.children.length === 0 && (e.innerText || '').trim() === LABEL).pop();
const r = leaf.getBoundingClientRect();
let x = r.left + r.width / 2, y = r.top + r.height / 2, f = MID;
while (f !== top) { const fr = f.frameElement.getBoundingClientRect(); x += fr.left; y += fr.top; f = f.parent; }
LABEL.replace(/\W/g, '_') + ' ' + Math.round(x) + ' ' + Math.round(y);
