import os, html, sys
d = '/tmp/mdrender/gallery'
gifs = sorted(f for f in os.listdir(d) if f.endswith('.gif'))
cells = []
for g in gifs:
    name = g[:-4]
    cells.append(f'''<figure>
      <img src="{html.escape(g)}" loading="lazy">
      <figcaption>{html.escape(name)}</figcaption></figure>''')
doc = f'''<!doctype html><meta charset="utf-8">
<title>Milkdrop reference gallery ({len(gifs)})</title>
<style>
 body{{background:#111;color:#ccc;font:13px/1.4 -apple-system,sans-serif;margin:16px}}
 h1{{font-size:15px;font-weight:600}}
 .grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}}
 figure{{margin:0;background:#000;border:1px solid #222;border-radius:6px;overflow:hidden}}
 img{{width:100%;display:block;background:#000}}
 figcaption{{padding:6px 8px;font-size:11px;color:#9ad;word-break:break-word}}
</style>
<h1>Milkdrop reference gallery — {len(gifs)} presets (faithful butterchurn renders, real-music-driven)</h1>
<div class="grid">{''.join(cells)}</div>'''
open(os.path.join(d,'index.html'),'w').write(doc)
print(f'gallery: file://{d}/index.html  ({len(gifs)} gifs)')
