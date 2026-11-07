## The interactive page of the swimlane picture: one self-contained HTML file (style, script and
## the four drawings in it, nothing fetched). This module holds only the page's template; the
## drawing is `swimlane.render` and `swimlane.page` fills the template in.

const pageTemplate* = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><!--TITLE--></title>
<style>
:root{--bg:#fbfbf9;--panel:#f1f2f0;--ink:#1b1f24;--dim:#5b6470;--rule:#d5d8dc;--accent:#2f6fdb;--onaccent:#fff}
@media (prefers-color-scheme:dark){:root{--bg:#16191d;--panel:#1d2126;--ink:#e6e8eb;--dim:#9aa3ad;--rule:#323840;--accent:#6aa2ff;--onaccent:#0b1220}}
*{box-sizing:border-box}
html,body{height:100%;margin:0}
body{background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif;display:flex;flex-direction:column;min-width:0}
header{padding:10px 16px 8px;border-bottom:1px solid var(--rule);display:flex;flex-wrap:wrap;gap:4px 18px;align-items:baseline}
header h1{font-size:16px;margin:0;font-weight:650}
header .sub{color:var(--dim);font-size:12.5px;min-width:0}
.bar{display:flex;flex-wrap:wrap;gap:8px 16px;padding:8px 16px;border-bottom:1px solid var(--rule);align-items:center;background:var(--panel)}
.grp{display:flex;align-items:center;gap:6px;min-width:0;flex-wrap:wrap}
.grp>.t{color:var(--dim);font-size:11px;letter-spacing:.05em;text-transform:uppercase}
.seg{display:inline-flex;border:1px solid var(--rule);border-radius:7px;overflow:hidden}
.seg button{all:unset;cursor:pointer;padding:5px 12px;font-size:12.5px;background:var(--bg);border-right:1px solid var(--rule);white-space:nowrap;text-align:center}
.seg button:last-child{border-right:0}
.seg button[aria-pressed=true]{background:var(--accent);color:var(--onaccent)}
.seg button:focus-visible,.btn:focus-visible{outline:2px solid var(--accent);outline-offset:1px}
.chk{font-size:12.5px;display:inline-flex;gap:6px;align-items:center;cursor:pointer}
.btn{all:unset;cursor:pointer;padding:5px 12px;border:1px solid var(--rule);border-radius:7px;font-size:12.5px;background:var(--bg)}
.legend{display:flex;flex-wrap:wrap;gap:4px 10px;align-items:center;font-size:12px;color:var(--dim)}
.legend i{display:inline-block;width:12px;height:12px;border-radius:3px;border:1.5px solid;vertical-align:-2px;margin-right:4px}
main{flex:1;display:flex;min-height:0;min-width:0}
#stage{flex:1;position:relative;min-width:0;overflow:hidden;background:var(--bg);cursor:grab;touch-action:none;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
#stage.drag{cursor:grabbing}
.variant{position:absolute;inset:0}
.variant[hidden]{display:none}
.variant svg{display:block;width:100%;height:100%}
#hint{transition:opacity .4s;position:absolute;left:10px;bottom:8px;font-size:11.5px;color:var(--dim);background:var(--panel);padding:2px 8px;border-radius:6px;pointer-events:none}
aside{width:300px;flex:none;border-left:1px solid var(--rule);background:var(--panel);overflow:auto;padding:12px 14px;min-width:0}
aside h2{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--dim);margin:14px 0 6px;font-weight:600}
aside h2:first-child{margin-top:0}
#slices{list-style:none;margin:0;padding:0}
#slices li{padding:4px 8px;border-radius:6px;cursor:pointer;font-size:12.5px;display:flex;gap:6px}
#slices li:hover{background:var(--bg)}
#slices li.on{background:var(--accent);color:var(--onaccent)}
#slices li .n{opacity:.6;min-width:1.6em;text-align:right}
#info{font-size:12.5px}
#info pre{white-space:pre-wrap;word-break:break-word;background:var(--bg);border:1px solid var(--rule);border-radius:6px;padding:6px 8px;margin:6px 0;font:11.5px/1.4 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.mono{font:12px ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.chip{display:inline-block;padding:0 7px;border:1.5px solid;border-radius:5px;font-size:11px;letter-spacing:.04em;text-transform:uppercase}
.links a{cursor:pointer;color:var(--accent);margin-right:8px;white-space:nowrap;display:inline-block}
.dimtxt{color:var(--dim)}
/* the drawing */
/*EM-STYLE*/
.em-box{cursor:pointer}
.em-box:hover rect{stroke-width:3}
.em-reads{display:none}
.show-reads .em-reads{display:inline}
body.sel .em-box{opacity:.15}
body.sel .em-edge{opacity:.08}
body.sel .em-box.hl{opacity:1}
body.sel .em-edge.hl{opacity:1;stroke:var(--accent);stroke-width:2.4;display:inline}
body.sel .em-box.pick rect{stroke:var(--accent);stroke-width:3.5}
@media (pointer:coarse),(max-width:820px){
  .seg button,.btn{min-height:44px;padding:8px 14px;font-size:15px;display:inline-flex;align-items:center;justify-content:center}
  .chk{font-size:15px;min-height:44px}
  .chk input{width:24px;height:24px}
  #slices li{padding:12px 8px;font-size:15px}
  .links a{padding:8px 0}
}
@media (max-width:820px){
  html,body{height:auto}
  body{overflow-x:hidden}
  header{order:1}
  main{display:contents}
  #stage{order:2;flex:none;height:66vh;min-height:340px;border-bottom:1px solid var(--rule)}
  .bar{order:3;padding:8px 12px;gap:10px}
  aside{order:4;width:auto;border-left:0;overflow:visible;padding:14px 12px}
  .grp{width:100%}
  .seg{display:flex;flex:1}
  .seg button{flex:1}
  #hint{max-width:70%}
}
</style>
</head>
<body>
<header>
  <h1><!--TITLE--></h1>
  <span class="sub" id="sub"></span>
</header>
<div class="bar">
  <div class="grp"><span class="t">Detail</span><div class="seg" id="seg-detail">
    <button data-v="n" aria-pressed="true">Names</button><button data-v="f" aria-pressed="false">+ Fields</button></div></div>
  <div class="grp"><span class="t">Density</span><div class="seg" id="seg-density">
    <button data-v="c" aria-pressed="true">Compact</button><button data-v="s" aria-pressed="false">Spacious</button></div></div>
  <div class="grp"><span class="t">Arrows</span>
    <label class="chk"><input type="checkbox" id="c-reads"> view read by command or query</label></div>
  <div class="grp"><button class="btn" id="b-fit">Fit all</button><button class="btn" id="b-fitw">Fit width</button><button class="btn" id="b-one">100%</button><button class="btn" id="b-clear">Clear highlight</button></div>
  <div class="legend" id="legend"></div>
</div>
<main>
  <div id="stage">
<!--VARIANTS-->
    <div id="hint">drag to pan · pinch or wheel to zoom · tap a box or a story to light up its arrows</div>
  </div>
  <aside>
    <h2>Selected</h2>
    <div id="info"><span class="dimtxt">Tap a box. Its arrows and neighbours light up, the rest fades.</span></div>
    <h2>Stories</h2>
    <ol id="slices"></ol>
  </aside>
</main>
<script>
const MODEL = /*DATA*/null;
(() => {
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const KINDS = ['screen','processor','command','event','view','query'];
const COLOUR = /*COLOURS*/null;
const S = {detail: MODEL.init.fields ? 'f' : 'n', density: MODEL.init.spacious ? 's' : 'c', sel: null, slice: null};
const views = {};   // variant key -> {scale, x0, y0, moved}
const stage = $('#stage');
const key = () => `${S.density}-${S.detail}`;
const curSvg = () => $(`.variant[data-key="${key()}"] svg`);
const esc = t => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;');

$('#sub').textContent = MODEL.counts;
const dark = matchMedia('(prefers-color-scheme:dark)');
function paintLegend() {
  const c = COLOUR[dark.matches ? 'dark' : 'light'];
  $('#legend').innerHTML = KINDS.map(k => `<span><i style="background:${c[k][0]};border-color:${c[k][1]}"></i>${k}</span>`).join('') +
    '<span class="mono">solid: produces, consumes, issues, offers, shows · dashed: reads</span>';
}
paintLegend(); dark.addEventListener('change', paintLegend);

function setVB(svg, v) {
  const r = stage.getBoundingClientRect();
  svg.setAttribute('viewBox', `${v.x0} ${v.y0} ${r.width / v.scale} ${r.height / v.scale}`);
}
function fit(mode) {
  const svg = curSvg(), r = stage.getBoundingClientRect();
  if (!svg || r.width === 0) return;
  const W = +svg.dataset.w, H = +svg.dataset.h;
  const v = views[key()] || (views[key()] = {});
  if (mode === 'w') { v.scale = r.width / W; v.x0 = 0; v.y0 = 0; }
  else if (mode === '1') { v.scale = 1; v.x0 = 0; v.y0 = 0; }
  else { v.scale = Math.min(r.width / W, r.height / H) * 0.97; v.x0 = (W - r.width / v.scale) / 2; v.y0 = (H - r.height / v.scale) / 2; }
  v.moved = mode !== 'a';
  setVB(svg, v);
}
function show() {
  const k = key();
  $$('.variant').forEach(d => d.hidden = d.dataset.key !== k);
  $$('#seg-detail button').forEach(b => b.setAttribute('aria-pressed', b.dataset.v === S.detail));
  $$('#seg-density button').forEach(b => b.setAttribute('aria-pressed', b.dataset.v === S.density));
  const v = views[k];
  if (v && v.scale) setVB(curSvg(), v); else fit('a');
  apply();
}

// ---- pan and zoom with pointer events: mouse drag pans, wheel zooms, one finger pans, two pinch
const ptrs = new Map();
let g = null, dragged = false;
const dist = () => { const [a, b] = [...ptrs.values()]; return Math.hypot(a.x - b.x, a.y - b.y); };
const mid = () => { const [a, b] = [...ptrs.values()]; return {x: (a.x + b.x) / 2, y: (a.y + b.y) / 2}; };
function zoomAt(v, px, py, k) {
  const wx = v.x0 + px / v.scale, wy = v.y0 + py / v.scale;
  v.scale = Math.min(8, Math.max(0.03, v.scale * k));
  v.x0 = wx - px / v.scale; v.y0 = wy - py / v.scale; v.moved = true;
}
stage.addEventListener('pointerdown', e => {
  $('#hint').style.opacity = 0;
  if (e.pointerType === 'mouse' && e.button !== 0) return;
  ptrs.set(e.pointerId, {x: e.clientX, y: e.clientY});
  if (ptrs.size === 1) g = {mode: 'wait', sx: e.clientX, sy: e.clientY};
  else if (ptrs.size === 2) { g = {mode: 'pinch', d: dist(), m: mid()}; dragged = true; }
});
stage.addEventListener('pointermove', e => {
  if (!ptrs.has(e.pointerId) || !g) return;
  const prev = ptrs.get(e.pointerId), cur = {x: e.clientX, y: e.clientY};
  const v = views[key()], r = stage.getBoundingClientRect();
  if (g.mode === 'pinch' && ptrs.size >= 2) {
    ptrs.set(e.pointerId, cur);
    const d = dist(), m = mid();
    v.x0 -= (m.x - g.m.x) / v.scale; v.y0 -= (m.y - g.m.y) / v.scale;
    zoomAt(v, m.x - r.left, m.y - r.top, d / g.d);
    g.d = d; g.m = m; setVB(curSvg(), v); return;
  }
  ptrs.set(e.pointerId, cur);
  if (g.mode === 'wait') {
    if (Math.hypot(e.clientX - g.sx, e.clientY - g.sy) < 6) return;   // still a tap
    g.mode = 'pan'; dragged = true; stage.classList.add('drag');
    try { stage.setPointerCapture(e.pointerId); } catch (_) {}
  }
  if (g.mode === 'pan') { v.x0 -= (cur.x - prev.x) / v.scale; v.y0 -= (cur.y - prev.y) / v.scale; v.moved = true; setVB(curSvg(), v); }
});
const endPtr = e => {
  ptrs.delete(e.pointerId);
  if (ptrs.size === 0) { g = null; stage.classList.remove('drag'); setTimeout(() => dragged = false, 0); }
  else if (ptrs.size === 1) { const [p] = [...ptrs.values()]; g = {mode: 'pan', sx: p.x, sy: p.y}; }
};
stage.addEventListener('pointerup', endPtr); stage.addEventListener('pointercancel', endPtr);
stage.addEventListener('wheel', e => {
  e.preventDefault();
  const v = views[key()], r = stage.getBoundingClientRect();
  if (!v) return;
  zoomAt(v, e.clientX - r.left, e.clientY - r.top, Math.exp(-e.deltaY * 0.0015)); setVB(curSvg(), v);
}, {passive: false});
new ResizeObserver(() => { const v = views[key()]; if (!v || !v.scale) fit('a'); else if (!v.moved) fit('a'); else setVB(curSvg(), v); }).observe(stage);

// ---- highlight a box's arrows, or a story's
const nbrs = {};
MODEL.edges.forEach(e => { (nbrs[e.f] ||= []).push(e); (nbrs[e.t] ||= []).push(e); });
function apply() {
  const svg = curSvg();
  document.body.classList.toggle('sel', !!(S.sel || S.slice !== null));
  if (!svg) return;
  $$('.hl,.pick', svg).forEach(n => n.classList.remove('hl', 'pick'));
  const nodes = new Set();
  let pairs = null, pick = null;
  if (S.slice !== null) {
    const st = MODEL.slices[S.slice].steps; st.forEach(n => nodes.add(n));
    pairs = new Set(st.slice(1).map((n, i) => st[i] + '>' + n));
  } else if (S.sel) {
    pick = S.sel; nodes.add(pick); (nbrs[pick] || []).forEach(e => { nodes.add(e.f); nodes.add(e.t); });
  } else return;
  $$('.em-box', svg).forEach(n => { if (nodes.has(n.dataset.name)) n.classList.add('hl'); if (n.dataset.name === pick) n.classList.add('pick'); });
  $$('.em-edge', svg).forEach(p => {
    const on = pairs ? pairs.has(p.dataset.from + '>' + p.dataset.to) : (p.dataset.from === pick || p.dataset.to === pick);
    if (on) p.classList.add('hl');
  });
}
const links = names => names.length ? `<span class="links">${[...new Set(names)].map(n => `<a data-go="${esc(n)}">${esc(n)}</a>`).join('')}</span>` : '<span class="dimtxt">none</span>';
function info(n) {
  const b = MODEL.blocks[n]; if (!b) return;
  const out = nbrs[n] || [];
  const inSl = MODEL.slices.map((s, i) => [s, i]).filter(([s]) => s.steps.includes(n));
  $('#info').innerHTML =
    `<div><span class="chip" style="border-color:${COLOUR[dark.matches ? 'dark' : 'light'][b.kind][1]}">${b.kind}</span> <b class="mono">${esc(n)}</b></div>` +
    `<pre>${esc(b.line)}</pre>` +
    `<div><span class="dimtxt">comes from</span> ${links(out.filter(e => e.t === n).map(e => e.f))}</div>` +
    `<div><span class="dimtxt">goes to</span> ${links(out.filter(e => e.f === n).map(e => e.t))}</div>` +
    `<div style="margin-top:6px"><span class="dimtxt">in stories</span> ${inSl.length ? `<span class="links">${inSl.map(([s, i]) => `<a data-sl="${i}">${esc(s.name)}</a>`).join('')}</span>` : '<b>none</b>'}</div>`;
}
function sliceInfo(i) {
  const s = MODEL.slices[i];
  $('#info').innerHTML = `<div><b>${esc(s.name)}</b></div><div class="mono" style="margin-top:4px">${s.steps.map(x => `<a data-go="${esc(x)}" style="cursor:pointer;color:var(--accent)">${esc(x)}</a>`).join(' → ')}</div>`;
}
const hint = '<span class="dimtxt">Tap a box. Its arrows and neighbours light up, the rest fades.</span>';
function mark() { $$('#slices li').forEach(li => li.classList.toggle('on', +li.dataset.i === S.slice)); }
function pickBlock(n) { S.sel = n; S.slice = null; info(n); mark(); apply(); }
function pickSlice(i) {
  if (S.slice === i) { S.slice = null; $('#info').innerHTML = hint; mark(); apply(); return; }
  S.slice = i; S.sel = null; sliceInfo(i); mark(); apply();
}
document.addEventListener('click', e => {
  if (dragged && e.target.closest('#stage')) return;
  const go = e.target.closest('[data-go]'), sl = e.target.closest('[data-sl]'), nd = e.target.closest('.em-box');
  if (go) pickBlock(go.dataset.go);
  else if (sl) pickSlice(+sl.dataset.sl);
  else if (nd) pickBlock(nd.dataset.name);
});
$('#slices').innerHTML = MODEL.slices.map((s, i) => `<li data-i="${i}" title="${esc(s.steps.join(' → '))}"><span class="n">${i + 1}</span><span>${esc(s.name)}</span></li>`).join('');
$('#slices').addEventListener('click', e => { const li = e.target.closest('li'); if (li) pickSlice(+li.dataset.i); });
$('#b-clear').onclick = () => { S.sel = null; S.slice = null; $('#info').innerHTML = hint; mark(); apply(); };

// ---- the switches
$('#seg-detail').onclick = e => { const b = e.target.closest('button'); if (b) { S.detail = b.dataset.v; show(); } };
$('#seg-density').onclick = e => { const b = e.target.closest('button'); if (b) { S.density = b.dataset.v; show(); } };
$('#b-fit').onclick = () => fit('a'); $('#b-fitw').onclick = () => fit('w'); $('#b-one').onclick = () => fit('1');
$('#c-reads').onchange = e => document.body.classList.toggle('show-reads', e.target.checked);
if (MODEL.init.reads) { $('#c-reads').checked = true; document.body.classList.add('show-reads'); }
show();
})();
</script>
</body>
</html>
"""
