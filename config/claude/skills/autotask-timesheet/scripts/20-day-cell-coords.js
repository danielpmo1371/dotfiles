// Viewport coordinates of the Mon cell in the MBIE row (any day cell opens the weekly popup).
// Run 00-hook.js first, then computer.left_click at the returned coordinates.
const LV = top.frames[1].frames[0].frames[1];
const row = [...LV.document.querySelectorAll('tr')].find(t => /FDD SoW8/.test(t.innerText));
const cell = row.children[6];
const r = cell.getBoundingClientRect();
let x = r.left + r.width / 2, y = r.top + r.height / 2, f = LV;
while (f !== top) { const fr = f.frameElement.getBoundingClientRect(); x += fr.left; y += fr.top; f = f.parent; }
'monCenter ' + Math.round(x) + ' ' + Math.round(y);
