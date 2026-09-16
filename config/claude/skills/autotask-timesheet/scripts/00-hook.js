// Install the window.open hook on every same-origin frame. Run IMMEDIATELY before a real click.
top.__popups = [];
(function hook(w){ try{ if(!w.__hooked){ w.__o = w.open;
  w.open = function(){ var r = w.__o.apply(w, arguments); top.__popups.push(r); return r; };
  w.__hooked = true; } for (let i = 0; i < w.frames.length; i++) hook(w.frames[i]); } catch(e){} })(top);
'hooked ' + !!top.__hooked;
