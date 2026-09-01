#!/usr/bin/env python3
"""Build docs/reviews/DS.1/index.html from before/ + after/ PNG pairs."""
import html, pathlib, sys, json

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "docs/reviews/DS.1")
NOTES = json.loads((ROOT / "notes.json").read_text()) if (ROOT / "notes.json").exists() else {}
ORDER = json.loads((ROOT / "order.json").read_text()) if (ROOT / "order.json").exists() else []

before = {p.stem: p for p in sorted((ROOT / "before").glob("*.png"))}
after  = {p.stem: p for p in sorted((ROOT / "after").glob("*.png"))}
names  = list(ORDER)
names += [n for n in sorted(set(before) | set(after)) if n not in names]

rows = []
for n in names:
    b = f'<img src="before/{n}.png" alt="{html.escape(n)} before">' if n in before else '<div class="missing">not captured</div>'
    a = f'<img src="after/{n}.png" alt="{html.escape(n)} after">' if n in after else '<div class="missing">not captured</div>'
    note = NOTES.get(n, "")
    rows.append(f"""<section id="{html.escape(n)}">
<h2>{html.escape(NOTES.get(n + '.title', n.replace('_', ' ')))}</h2>
<div class="pair"><figure><figcaption>before — main</figcaption>{b}</figure>
<figure><figcaption>after — DS.1</figcaption>{a}</figure></div>
<p class="note">{note}</p></section>""")

nav = " · ".join(f'<a href="#{html.escape(n)}">{html.escape(n.replace("_"," "))}</a>' for n in names)

(ROOT / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>DS.1 — before / after</title>
<style>
:root {{ color-scheme: dark; --canvas:#0b0c10; --surface:#14151a; --raised:#1d1f25;
  --line:#34363f; --text:#f4f6f1; --text2:#c5c9c3; --text3:#a4a8a2; --accent:#7f6aff; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; padding:0 clamp(1rem,4vw,3rem) 6rem; background:var(--canvas); color:var(--text);
  font:16px/1.55 system-ui, -apple-system, sans-serif; }}
header {{ padding:3rem 0 1.5rem; border-bottom:1px solid var(--line); margin-bottom:2rem; }}
h1 {{ font-size:2rem; margin:0 0 .5rem; font-weight:600; letter-spacing:-.02em; }}
header p {{ color:var(--text2); max-width:68ch; margin:.5rem 0; }}
nav {{ font-size:.8rem; color:var(--text3); line-height:2; margin-top:1rem; }}
nav a {{ color:var(--text3); text-decoration:none; border-bottom:1px solid transparent; }}
nav a:hover {{ color:var(--accent); border-bottom-color:var(--accent); }}
section {{ margin:0 0 3.5rem; scroll-margin-top:1rem; }}
h2 {{ font-size:1.05rem; font-weight:600; margin:0 0 .75rem; color:var(--text); }}
.pair {{ display:grid; grid-template-columns:1fr 1fr; gap:1rem; align-items:start; }}
@media (max-width:900px) {{ .pair {{ grid-template-columns:1fr; }} }}
figure {{ margin:0; background:var(--surface); border:1px solid var(--line); border-radius:12px; overflow:hidden; }}
figcaption {{ font-size:.7rem; letter-spacing:.04em; text-transform:uppercase; color:var(--text3);
  padding:.6rem .9rem; background:var(--raised); border-bottom:1px solid var(--line); }}
img {{ display:block; width:100%; height:auto; }}
.missing {{ padding:3rem 1rem; text-align:center; color:var(--text3); font-size:.85rem; }}
.warn {{ color:var(--text2); background:#282400; border:1px solid #8c7600;
  border-radius:12px; padding:.9rem 1.1rem; max-width:80ch; font-size:.9rem; }}
.warn strong {{ color:#ffd60a; }}
.note {{ color:var(--text2); font-size:.9rem; max-width:80ch; margin:.9rem 0 0; }}
</style></head><body>
<header>
<h1>DS.1 — the app adopts UzumeTokens</h1>
<p>Presentation only. Nothing the user can do changed: no state machine, publisher, view model,
accessibility identifier, copy string, keyboard shortcut or test expectation was touched. Every
pair below is the same screen at the same window size, before and after the token swap.</p>
<p><strong>before</strong> is <code>main</code> at <code>caa69638</code>. <strong>after</strong> is the DS.1 branch.
Uzume is always dark (D-231 option A), so there is one appearance to review. This Mac is set to
<em>Light</em> appearance, which is why the window chrome changes.</p>
<p class="warn"><strong>Twelve of twenty states are captured.</strong> Eight are not: four need a
live connector credential, a failing track or a revoked permission grant to reach at all, three are
Settings sub-panes that hold no retokenized code, and one (Ready) is passed through faster than the
local-file route can be sampled. Each says so under its own heading.</p>
<nav>{nav}</nav>
</header>
{"".join(rows)}
</body></html>""")
print(f"wrote {ROOT/'index.html'} — {len(names)} states, {len(before)} before, {len(after)} after")
