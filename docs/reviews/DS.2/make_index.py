#!/usr/bin/env python3
"""Build docs/reviews/DS.2/index.html from before/ + after/ PNG pairs.

Self-contained output: no build step, no network, opens offline from the file
system. Adapted from DS.1's generator, plus the VoiceOver before/after table.
"""
import html, json, pathlib, sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "docs/reviews/DS.2")
load = lambda n, d: json.loads((ROOT / n).read_text()) if (ROOT / n).exists() else d
NOTES, ORDER, VO = load("notes.json", {}), load("order.json", []), load("voiceover.json", {})

before = {p.stem for p in (ROOT / "before").glob("*.png")}
after = {p.stem for p in (ROOT / "after").glob("*.png")}
names = list(ORDER) + [n for n in sorted(before | after) if n not in ORDER]

MISSING = ('<div class="missing">not captured — the machine was at the lock screen '
           'for the whole DS.2 session</div>')


def fig(kind, name, present, caption):
    img = (f'<img src="{kind}/{name}.png" alt="{html.escape(name)} {kind}" loading="lazy">'
           if present else MISSING)
    return f"<figure><figcaption>{caption}</figcaption>{img}</figure>"


sections = []
for n in names:
    title = NOTES.get(n + ".title", n.replace("_", " "))
    note = NOTES.get(n, "")
    sections.append(
        f'<section id="{html.escape(n)}"><h2>{html.escape(title)}</h2>'
        f'<div class="pair">{fig("before", n, n in before, "before — main")}'
        f'{fig("after", n, n in after, "after — DS.2")}</div>'
        + (f'<p class="note">{html.escape(note)}</p>' if note else "")
        + "</section>")

rows = []
for r in VO.get("rows", []):
    hint = lambda v: (f'<span class="hint">{html.escape(v)}</span>' if v
                      else '<span class="none">— no hint announced —</span>')
    cls = "changed" if r["change"] != "unchanged" else ""
    rows.append(
        f'<tr class="{cls}"><th>{html.escape(r["tile"])}<code>{html.escape(r["id"])}</code></th>'
        f'<td>{html.escape(r["before_label"])}<br>{hint(r["before_hint"])}</td>'
        f'<td>{html.escape(r["after_label"])}<br>{hint(r["after_hint"])}</td>'
        f'<td class="delta">{html.escape(r["change"])}</td></tr>')

nav = " · ".join(f'<a href="#{html.escape(n)}">{html.escape(n.replace("_", " "))}</a>'
                 for n in names)

(ROOT / "index.html").write_text(f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DS.2 — SourceChoice, before / after</title>
<style>
:root {{ color-scheme: dark; --canvas:#0b0c10; --surface:#14151a; --raised:#1d1f25;
  --line:#34363f; --text:#f4f6f1; --text2:#c5c9c3; --text3:#a4a8a2; --accent:#7f6aff;
  --warn:#ffd60a; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; padding:0 clamp(1rem,4vw,3rem) 6rem; background:var(--canvas); color:var(--text);
  font:16px/1.55 system-ui, -apple-system, sans-serif; }}
header {{ padding:3rem 0 1.5rem; border-bottom:1px solid var(--line); margin-bottom:2rem; }}
h1 {{ font-size:2rem; margin:0 0 .5rem; font-weight:600; letter-spacing:-.02em; }}
h2 {{ font-size:1.05rem; font-weight:600; margin:0 0 .75rem; }}
header p {{ color:var(--text2); max-width:68ch; margin:.5rem 0; }}
nav {{ font-size:.8rem; color:var(--text3); line-height:2; margin-top:1rem; }}
nav a {{ color:var(--text3); text-decoration:none; border-bottom:1px solid transparent; }}
nav a:hover {{ color:var(--text); border-bottom-color:var(--accent); }}
.banner {{ border:1px solid var(--warn); background:#282400; color:#ffe873; padding:1rem 1.25rem;
  border-radius:12px; margin:1.5rem 0; max-width:80ch; }}
.banner strong {{ color:var(--warn); }}
section {{ margin:0 0 3rem; padding-top:1rem; }}
.pair {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(320px,1fr)); gap:1rem; }}
figure {{ margin:0; background:var(--surface); border:1px solid var(--line); border-radius:12px;
  overflow:hidden; }}
figcaption {{ font-size:.75rem; color:var(--text3); padding:.6rem .8rem;
  border-bottom:1px solid var(--line); text-transform:uppercase; letter-spacing:.06em; }}
img {{ display:block; width:100%; height:auto; }}
.missing {{ padding:3rem 1rem; text-align:center; color:var(--text3); font-size:.85rem;
  font-style:italic; }}
.note {{ color:var(--text2); font-size:.9rem; max-width:80ch; margin:.9rem 0 0; }}
table {{ border-collapse:collapse; width:100%; font-size:.85rem; }}
th, td {{ text-align:left; vertical-align:top; padding:.7rem .8rem; border-bottom:1px solid var(--line); }}
thead th {{ color:var(--text3); text-transform:uppercase; letter-spacing:.06em; font-size:.7rem; }}
tbody th {{ font-weight:600; width:20%; }}
tbody th code {{ display:block; font-weight:400; color:var(--text3); font-size:.72rem; margin-top:.25rem; }}
tr.changed {{ background:rgba(127,106,255,.09); }}
.hint {{ color:var(--accent); }}
.none {{ color:var(--text3); font-style:italic; }}
.delta {{ color:var(--text3); white-space:nowrap; }}
.scroll {{ overflow-x:auto; }}
</style></head><body>
<header>
<h1>DS.2 — <code>SourceChoice</code>: one tile, four affordances</h1>
<p><code>ConnectorTileView</code> and the private <code>LocalSourceActionTile</code> are replaced by
one component. Two things to judge, both consequences of having one component instead of two.</p>
<p><strong>1. The connector tiles now respond to hover.</strong> They had no hover state; the local
tiles did. Sharing one interactive treatment gives the connector tiles the lift the local tiles
always had.</p>
<p><strong>2. The local tiles now announce a VoiceOver hint.</strong> "Opens a file chooser". They
announced nothing after their label before, while the connector tiles on the previous screen
announced one — so a Curator using VoiceOver got guidance on the first source screen and silence on
the second. This is the DECISION-NEEDED's default (option A); the wording is the part to judge.</p>
<div class="banner"><strong>Captures are missing, and the reason is not the work.</strong>
The Mac was at the lock screen for the entire DS.2 session, so every display capture returns black
and the app's view hierarchy is absent from the accessibility tree — only its menu bar is reachable.
Unlock the machine and run <code>docs/reviews/DS.2/capture.sh before</code> (on <code>main</code>)
and <code>… after</code> (on this branch), then re-run <code>make_index.py</code>. Every pair below
fills in. The VoiceOver table is derived from source and is exact; it still wants one live
confirmation.</div>
<nav>{nav}</nav>
</header>

<section id="voiceover"><h2>VoiceOver — label, then hint</h2>
<div class="scroll"><table>
<thead><tr><th>Tile</th><th>Before — <code>main</code></th><th>After — DS.2</th><th>Δ</th></tr></thead>
<tbody>{"".join(rows)}</tbody>
</table></div>
<p class="note">{html.escape(VO.get("note", ""))}</p></section>

{"".join(sections)}
</body></html>""")
print(f"index.html written — {len(names)} pairs, {len(before)} before, {len(after)} after")
