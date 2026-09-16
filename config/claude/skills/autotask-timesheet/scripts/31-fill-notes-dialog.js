// Fill the open Enter Notes dialog. GATE: HOURS and TEXT must be copied verbatim from Daniel's
// approval message. Throws if left null, or if the day already has hours (never overwrite).
const HOURS = null;   // e.g. '8.0'
const TEXT = null;    // approved summary text
if (!HOURS || !TEXT) throw new Error('unapproved: set HOURS and TEXT from Daniel\'s approval message');
const w = top.__popups[top.__popups.length - 1]; const d = w.document;
const txt = e => (e.innerText || e.textContent || '').trim();
const dlg = [...d.querySelectorAll('body *')].find(e => /Dialog/i.test(e.className) && e.offsetWidth > 200 && e.offsetHeight > 100 && /Enter Notes/i.test(txt(e)));
const hours = dlg.querySelector('input.DecimalBox2');
if (hours.value && parseFloat(hours.value) > 0) throw new Error('day already has ' + hours.value + ' hours - stop and ask Daniel');
const summary = [...dlg.querySelectorAll('.ContentEditable2')].filter(e => e.isContentEditable)[0];
const fire = (el, types) => types.forEach(t => el.dispatchEvent(new w.Event(t, { bubbles: true })));
hours.focus(); hours.value = HOURS; fire(hours, ['input', 'change', 'blur']);
summary.focus(); summary.innerHTML = ''; summary.appendChild(d.createTextNode(TEXT)); fire(summary, ['input', 'keyup', 'change', 'blur']);
await new Promise(r => setTimeout(r, 500));
'title ' + txt(dlg).split('\n')[0].replace(/[^A-Za-z0-9 \/-]/g, '') + ' hours ' + hours.value + ' summaryLen ' + txt(summary).length;
