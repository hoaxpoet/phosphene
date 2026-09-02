#!/usr/bin/env python3
"""Assemble docs/reviews/DS.4/index.html — self-contained (images and the recording
inlined as data URIs, no build step, renders offline).

    python3 docs/reviews/DS.4/build_page.py
"""
import base64, os, re

ROOT = os.path.dirname(os.path.abspath(__file__))


def data_uri(rel, mime):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        return None
    with open(path, "rb") as fh:
        return f"data:{mime};base64,{base64.b64encode(fh.read()).decode()}"


def img(rel, alt):
    """Inline a 900px-wide JPEG copy of a capture (the 2× PNGs are ~1 MB each; the page
    must stay openable). Copies are cached under _web/, which is not tracked."""
    src = os.path.join(ROOT, rel)
    if not os.path.exists(src):
        return f'<div class="missing">missing: {rel}</div>'
    web = os.path.join(ROOT, "_web", rel.replace("/", "__") + ".jpg")
    os.makedirs(os.path.dirname(web), exist_ok=True)
    if not os.path.exists(web) or os.path.getmtime(web) < os.path.getmtime(src):
        import subprocess
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "82",
                        "--resampleWidth", "900", src, "--out", web],
                       check=True, capture_output=True)
    with open(web, "rb") as fh:
        uri = f"data:image/jpeg;base64,{base64.b64encode(fh.read()).decode()}"
    return f'<img src="{uri}" alt="{alt}">'


STATES = [
    ("preparation-early", "Early — nothing heard yet", "reachable",
     "Resolving and downloading; the cave is shut and the frame is genuinely dark."),
    ("preparation-mid", "Mid — two heard, below the three-track threshold", "reachable",
     "A pinprick. The first prism just escaping. No “Start now” yet."),
    ("preparation-threeReady", "Three ready — “Start now” unlocks", "reachable",
     "The opening reaches its first proper stop the moment the listener can start."),
    ("preparation-halfway", "Halfway — partially planned", "reachable",
     "Wider, more vibrant, more specific: five tracks’ character in the light."),
    ("preparation-previewNotFound", "One track has no preview", "reachable",
     "Inline on its row in the detailed view; a count line in the mysterious view that opens the detailed one."),
    ("preparation-stemSeparationFailed", "One track’s stems failed", "reachable",
     "Inline on its row. A partial track still counts as usable, so it is not in the failure count."),
    ("preparation-banner", "The banner slot", "trigger not reachable",
     "The rate-limit trigger the harness uses is never emitted by the preparer; the two reachable banners need a real clock. The slot and its placement are what this evidences."),
    ("preparation-recovery", "Every track failed — RecoveryScreen", "reachable",
     "Identical in both views: the blocking branch sits above the preference."),
]


def a11y_table(rel):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        return f"<p class='missing'>missing: {rel}</p>"
    rows = [l.split("\t") for l in open(path).read().strip().split("\n")]
    head, body = rows[0], rows[1:]
    h = "<tr>" + "".join(f"<th>{c}</th>" for c in head) + "</tr>"
    b = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in body)
    return f"<table class='a11y'>{h}{b}</table>"


def timing_table():
    md = open(os.path.join(ROOT, "TIMING.md")).read()
    lines = [l for l in md.split("\n") if l.startswith("|")]
    if not lines:
        return "<p class='missing'>TIMING.md has no table</p>"
    out = ["<table>"]
    for i, l in enumerate(lines):
        cells = [c.strip() for c in l.strip("|").split("|")]
        if set("".join(cells)) <= set("-: "):
            continue
        tag = "th" if i == 0 else "td"
        out.append("<tr>" + "".join(f"<{tag}>{c}</{tag}>" for c in cells) + "</tr>")
    out.append("</table>")
    return "".join(out)


def timing_deltas():
    md = open(os.path.join(ROOT, "TIMING.md")).read()
    m = re.search(r"\*\*Deltas:\*\*(.*?)\n\n", md, re.S)
    return m.group(1).strip() if m else ""


def flash_numbers():
    path = os.path.join(ROOT, "FLASH.txt")
    return open(path).read().strip() if os.path.exists(path) else "(FLASH.txt missing)"


recording = data_uri("mysterious-preparation.mp4", "video/mp4")
video_block = (
    f'<video controls playsinline src="{recording}"></video>'
    if recording else "<p class='missing'>recording missing: mysterious-preparation.mp4</p>"
)

cards = []
for name, label, reach, note in STATES:
    rc = "reach" if reach == "reachable" else "unreach"
    cards.append(f"""
  <figure class="state">
    <figcaption><span class="lbl">{label}</span> <span class="tag {rc}">{reach}</span>
      <span class="note">{note}</span></figcaption>
    <div class="shots three">
      <div><span class="ba">before</span>{img(f"before/{name}.png", label + " before")}</div>
      <div><span class="ba">after · mysterious</span>{img(f"after/{name}-mysterious.png", label + " mysterious")}</div>
      <div><span class="ba">after · detailed</span>{img(f"after/{name}-detailed.png", label + " detailed")}</div>
    </div>
  </figure>""")

live = []
for name, label in [("live-early", "seconds in — the first track lands"),
                    ("live-threeReady", "“Start now” unlocks"),
                    ("live-mid", "about ninety seconds in"),
                    ("live-late", "late in the wait")]:
    before_rel = "before/live-early.png" if name == "live-early" else None
    before_cell = (f'<div><span class="ba">before (main)</span>{img(before_rel, label)}</div>'
                   if before_rel else '<div><span class="ba">before (main)</span><div class="missing">only the first seconds were captured on main</div></div>')
    detailed_rel = f"after/{name}-detailed.png"
    detailed_cell = (f'<div><span class="ba">after · detailed</span>{img(detailed_rel, label)}</div>'
                     if os.path.exists(os.path.join(ROOT, detailed_rel)) else "")
    live.append(f"""
  <figure class="state">
    <figcaption><span class="lbl">Live — {label}</span>
      <span class="note">Screenshots of the running app on the 40-track playlist.</span></figcaption>
    <div class="shots{' three' if detailed_cell else ''}">
      {before_cell}
      <div><span class="ba">after · mysterious</span>{img(f"after/{name}-mysterious.png", label)}</div>
      {detailed_cell}
    </div>
  </figure>""")

html = f"""<!doctype html>
<meta charset="utf-8">
<title>DS.4 — the preparation screen becomes the overture</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin:0; padding:32px clamp(16px,4vw,64px); background:#0b0c10; color:#f4f6f1;
         font:15px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }}
  h1 {{ font-size:28px; margin:0 0 4px; letter-spacing:-.01em; }}
  .sub {{ color:#a4a8a2; margin:0 0 28px; max-width:70ch; }}
  h2 {{ font-size:19px; margin:44px 0 16px; padding-bottom:8px; border-bottom:1px solid #2a2d33; }}
  .callout {{ border:1px solid #352b72; background:#15132a; color:#e8e6dd; padding:16px 20px;
              border-radius:10px; margin:0 0 20px; }}
  .callout h3 {{ margin:0 0 8px; font-size:16px; color:#a99bff; }}
  .callout p {{ margin:6px 0; }}
  .quote {{ font-size:22px; color:#f5c84c; margin:0 0 6px; }}
  .state {{ margin:0 0 28px; }}
  figcaption {{ display:flex; gap:8px; align-items:baseline; flex-wrap:wrap; margin-bottom:8px; }}
  .lbl {{ font-weight:600; }}
  .note {{ color:#a4a8a2; font-size:13px; flex-basis:100%; }}
  .tag {{ font-size:11px; text-transform:uppercase; letter-spacing:.05em;
          padding:2px 7px; border-radius:99px; border:1px solid; }}
  .reach {{ color:#67d6a2; border-color:#2e835e; background:#122b21; }}
  .unreach {{ color:#a4a8a2; border-color:#3a3d43; background:#17191e; }}
  .shots {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; }}
  .shots.three {{ grid-template-columns:1fr 1fr 1fr; }}
  .shots > div {{ background:#000; border:1px solid #2a2d33; border-radius:8px; overflow:hidden; }}
  .ba {{ display:block; font-size:10px; text-transform:uppercase; letter-spacing:.08em;
         color:#a4a8a2; padding:5px 9px; background:#17191e; border-bottom:1px solid #2a2d33; }}
  img, video {{ display:block; width:100%; height:auto; }}
  video {{ border:1px solid #2a2d33; border-radius:8px; background:#000; }}
  table {{ border-collapse:collapse; width:100%; font-size:13px; margin:12px 0 8px; }}
  th,td {{ border:1px solid #2a2d33; padding:8px 10px; text-align:left; vertical-align:top; }}
  th {{ background:#17191e; font-weight:600; }}
  .a11y td:first-child {{ white-space:nowrap; }}
  pre {{ background:#14151a; border:1px solid #2a2d33; border-radius:8px; padding:12px 14px; font-size:12.5px; overflow:auto; }}
  .missing {{ color:#ff8a75; padding:12px; }}
  @media (max-width:900px) {{ .shots, .shots.three {{ grid-template-columns:1fr; }} }}
</style>
<h1>DS.4 — the preparation screen becomes the overture</h1>
<p class="sub">Before: a file-transfer dialog. After: a cave whose opening widens as Uzume hears the
playlist, or the list of what it heard — the listener chooses. Rendered from the built app at 2×;
the recording is the real app on a real 40-track playlist.</p>

<div class="callout">
  <p class="quote">“i want people to feel entertained and excited during preparation”</p>
  <h3>What you are judging</h3>
  <p>Whether the wait is entertaining and exciting — and whether the <strong>mysterious view holds
  for four minutes</strong>, the claim the whole direction rests on. Watch the recording at 1×
  before the stills.</p>
  <p>Two things you decided that the build follows exactly: <strong>“Start now” is a button</strong>
  (the cave signals readiness, never becomes the control), and <strong>the list is hidden in the
  mysterious view</strong> — failures surface as a count line that opens the detailed view.</p>
</div>

<h2>The mysterious view, in motion — a full preparation, 40 tracks</h2>
{video_block}
<p class="note">Recorded from the DS.4 build during the task 10 timing run. The opening is shut until
the first track is heard, cracks to a pinprick, opens properly when “Start now” unlocks, and keeps
deepening — more vibrant, more ribbed or more washed depending on what has been heard — until the
last track lands.</p>

<h2>Live — the real app, same playlist, before and after</h2>
{''.join(live)}

<h2>Every reachable state — before, mysterious, detailed</h2>
{''.join(cards)}

<h2>Did the overture tax the work it describes?</h2>
<p class="note">Same 40-track playlist, cold cache, nothing else running. From <code>docs/reviews/DS.4/TIMING.md</code>.</p>
{timing_table()}
<p><strong>Deltas:</strong> {timing_deltas()}</p>

<h2>Flash safety (D-157)</h2>
<pre>{flash_numbers()}</pre>
<p class="note">Measured in the MitosisSketchRenderTests §Criterion 4 idiom: the scene stepped frame
by frame through a scripted 40-track preparation with a four-track burst, mean luminance per
frame, gate max Δ/frame &lt; 0.05.</p>

<h2>VoiceOver — the declared labels, before and after</h2>
<h3>Before</h3>
{a11y_table("before/a11y-preparation.txt")}
<h3>After</h3>
{a11y_table("after/a11y-preparation.txt")}
<p class="note">Every existing preparation identifier is unchanged. The header and progress bar had no
labels to lose; the cave gains one element that says everything the light says.</p>
"""
open(os.path.join(ROOT, "index.html"), "w").write(html)
print("index.html written", len(html) // 1024, "KB")
