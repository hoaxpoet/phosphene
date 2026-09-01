import os

PAIRS = [
    ("The banner — every state a user can actually reach", [
        ("banner-rateLimited", "Preview rate limited", "reachable", "info"),
        ("banner-slowFirstTrack", "Slow first track", "reachable", "info"),
        ("banner-totalTimeout", "Total timeout", "reachable", "info"),
    ]),
    ("The banner — tones no routed error reaches (shown only to prove the tone now varies)", [
        ("banner-fatal-networkOffline", "If a fatal error were routed here", "not reachable", "danger"),
        ("banner-info-rePlanSucceeded", "Another info-severity error", "not reachable", "info"),
    ]),
    ("Toasts — where the degradation decision landed, and where DS.3a moved it back", [
        ("toast-info", "Info", "reachable", "info"),
        ("toast-warning", "Warning", "reachable", "warning"),
        (("toast-degradation", "toast-fatal"), "“No audio detected.” — reclassified fatal (DS.3a)", "reachable", "danger"),
        (("toast-degradation", "toast-degradation"), "Degradation — a dropped stem, which is what that severity actually means", "reachable", "warning"),
    ]),
    ("The blocking screen", [
        ("fullscreen-fatal-networkOffline", "Network offline", "reachable", "danger"),
        ("fullscreen-fatal-allTracksFailed", "All tracks failed", "reachable", "danger"),
        ("fullscreen-warning-spotifyUnreachable", "A warning-severity error", "not reachable", "warning"),
        ("fullscreen-degradation-stemSeparationFailed", "A degradation-severity error", "not reachable", "warning"),
        ("fullscreen-info-emptyPlaylist", "An info-severity error", "not reachable", "info"),
    ]),
    ("The inline notice", [
        ("inline-unsupportedFormat", "Unsupported format", "reachable", "danger"),
        ("inline-unreadable", "Unreadable file", "reachable", "danger"),
        ("inline-m3uParseFailed", "Playlist parse failed", "reachable", "danger"),
        ("inline-emptyFolder", "Empty folder", "reachable", "danger"),
    ]),
]

def a11y_table(path):
    rows = [l.split("\t") for l in open(path).read().strip().split("\n")]
    head, body = rows[0], rows[1:]
    h = "<tr>" + "".join(f"<th>{c}</th>" for c in head) + "</tr>"
    b = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in body)
    return f"<table class='a11y'>{h}{b}</table>"

blocks = []
for title, items in PAIRS:
    cards = []
    for name, label, reach, tone in items:
        before_name, after_name = name if isinstance(name, tuple) else (name, name)
        rc = "reach" if reach == "reachable" else "unreach"
        cards.append(f"""
      <figure class="pair">
        <figcaption><span class="lbl">{label}</span>
          <span class="tag {rc}">{reach}</span>
          <span class="tag tone-{tone}">after: {tone}</span></figcaption>
        <div class="shots">
          <div><span class="ba">before</span><img src="before/{before_name}.png" alt="{label} before"></div>
          <div><span class="ba">after</span><img src="after/{after_name}.png" alt="{label} after"></div>
        </div>
      </figure>""")
    blocks.append(f"<section><h2>{title}</h2>{''.join(cards)}</section>")

html = f"""<!doctype html>
<meta charset="utf-8">
<title>DS.3 — status placements, before and after</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin:0; padding:32px clamp(16px,4vw,64px); background:#0b0c10; color:#f4f6f1;
         font:15px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }}
  h1 {{ font-size:28px; margin:0 0 4px; letter-spacing:-.01em; }}
  .sub {{ color:#a4a8a2; margin:0 0 32px; }}
  h2 {{ font-size:19px; margin:44px 0 16px; padding-bottom:8px; border-bottom:1px solid #2a2d33; }}
  h3 {{ font-size:16px; margin:28px 0 10px; }}
  .callout {{ border:1px solid #8c7600; background:#282400; color:#ffd60a;
              padding:16px 20px; border-radius:10px; margin:0 0 20px; }}
  .callout.danger {{ border-color:#c55646; background:#321914; color:#ff8a75; }}
  .callout h3 {{ margin:0 0 8px; font-size:16px; color:inherit; }}
  .callout p {{ margin:6px 0; color:#e8e6dd; }}
  .callout.danger p {{ color:#f2ded9; }}
  .pair {{ margin:0 0 24px; }}
  figcaption {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-bottom:8px; }}
  .lbl {{ font-weight:600; }}
  .tag {{ font-size:11px; text-transform:uppercase; letter-spacing:.05em;
          padding:2px 7px; border-radius:99px; border:1px solid; }}
  .reach {{ color:#67d6a2; border-color:#2e835e; background:#122b21; }}
  .unreach {{ color:#a4a8a2; border-color:#3a3d43; background:#17191e; }}
  .tone-info {{ color:#64d2ff; border-color:#1976a3; background:#102735; }}
  .tone-warning {{ color:#ffd60a; border-color:#8c7600; background:#282400; }}
  .tone-danger {{ color:#ff8a75; border-color:#c55646; background:#321914; }}
  .shots {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; }}
  .shots > div {{ background:#000; border:1px solid #2a2d33; border-radius:8px; overflow:hidden; }}
  .ba {{ display:block; font-size:10px; text-transform:uppercase; letter-spacing:.08em;
         color:#a4a8a2; padding:5px 9px; background:#17191e; border-bottom:1px solid #2a2d33; }}
  img {{ display:block; width:100%; height:auto; }}
  table {{ border-collapse:collapse; width:100%; font-size:13px; margin:12px 0 8px; }}
  th,td {{ border:1px solid #2a2d33; padding:8px 10px; text-align:left; vertical-align:top; }}
  th {{ background:#17191e; font-weight:600; }}
  td code, th code {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:12px; }}
  .swatch {{ display:inline-block; width:10px; height:10px; border-radius:2px;
             margin-right:6px; vertical-align:-1px; border:1px solid #0006; }}
  .a11y td:first-child {{ white-space:nowrap; }}
  .note {{ color:#a4a8a2; font-size:13px; }}
  @media (max-width:720px) {{ .shots {{ grid-template-columns:1fr; }} }}
</style>
<h1>DS.3 — one severity vocabulary, four interruption levels</h1>
<p class="sub">Three colour maps became one. Before/after for every status surface in every
tone. Rendered from the built app at 2×; reachability noted per pair.</p>

<div class="callout danger">
  <h3>Read this first — the prompt predicted the wrong headline change</h3>
  <p>DS.3 expected the banner to flip from an amber fill with black text to the
  <strong>token warning</strong> treatment. It did not. Every banner a user can actually reach
  is now <strong>info blue</strong>.</p>
  <p>The three errors routed to the banner — preview rate limited, slow first track, total
  timeout — all carry <code>info</code> severity, not <code>warning</code>. None of them is named
  in <code>UserFacingError.severity</code>, so all three fall through to its <code>default</code>
  arm. The old banner hid this by being hard-coded amber regardless of severity; making it derive
  its tone from severity, which is what task 5 asked for, is what surfaced it.</p>
  <p><strong>This is in-scope behaviour, not a bug.</strong> DS.3 was explicitly barred from
  changing which severity an error has. If these three should read as caution rather than
  information, that is a change to <code>ErrorSeverity</code> in the engine — its own increment,
  and your call.</p>
</div>

<div class="callout">
  <h3>Settled, then sharpened — degradation is caution, but silence is fatal</h3>
  <p><strong>Option A approved</strong> (2026-09-01): <code>degradation</code> reads as caution
  everywhere, and <code>danger</code> is reserved for what actually stops Uzume delivering.</p>
  <p><strong>Then you pushed back on the silence toast, and you were right — DS.3a follows.</strong>
  Making that toast yellow surfaced something the increment had not looked at: it was red only
  because <code>PlaybackErrorBridge</code> hard-coded <code>.degradation</code> at the call site.
  The engine's own taxonomy rated <code>silenceExtended</code> a mere <strong>warning</strong> —
  milder than a dropped stem. The pixels and the model had disagreed about silence for months, and
  the tone work is what exposed it.</p>
  <p>So <code>silenceExtended</code> is now <code>fatal</code>, the toast enum gained the
  <code>fatal</code> case it was missing (the bridge had been folding fatal into degradation, which
  is why the distinction could never reach a view), and the toast is red again — this time because
  the taxonomy says so rather than because a call site did. VoiceOver now announces it as
  <em>&ldquo;Critical: No audio detected.&rdquo;</em> rather than <em>&ldquo;Alert: &hellip;&rdquo;</em>.</p>
</div>

<h2>The colour map — three maps resolved into one</h2>
<table>
<tr><th>Severity</th><th>Before: full-screen</th><th>Before: toast</th><th>Before: banner</th>
    <th>Before: inline</th><th>After: all four</th></tr>
<tr><td><code>info</code></td>
    <td><span class="swatch" style="background:#F4F6F1"></span>text primary<br><code>info.circle</code></td>
    <td><span class="swatch" style="background:#64D2FF"></span>#64D2FF</td>
    <td rowspan="4" class="note">Severity ignored entirely.<br><br>
        <span class="swatch" style="background:#FFD60A"></span>amber fill #FFD60A @ 88 %<br>
        <span class="swatch" style="background:#0B0C10"></span>near-black text #0B0C10<br><br>
        Every banner identical whatever went wrong.</td>
    <td rowspan="4" class="note">Severity not modelled.<br><br>
        <span class="swatch" style="background:#FF8A75"></span>pip always #FF8A75</td>
    <td><span class="swatch" style="background:#64D2FF"></span><strong>info</strong> — #64D2FF on #102735, border #1976A3<br><code>info.circle</code></td></tr>
<tr><td><code>warning</code></td>
    <td><span class="swatch" style="background:#FF9500"></span>system <code>.orange</code><br><code>exclamationmark.circle</code></td>
    <td><span class="swatch" style="background:#FFD60A"></span>#FFD60A</td>
    <td rowspan="2"><span class="swatch" style="background:#FFD60A"></span><strong>warning</strong> — #FFD60A on #282400, border #8C7600<br><code>exclamationmark.triangle</code></td></tr>
<tr><td><code>degradation</code></td>
    <td><span class="swatch" style="background:#FFCC00"></span>system <code>.yellow</code><br><code>exclamationmark.triangle</code></td>
    <td><span class="swatch" style="background:#FF8A75"></span>#FF8A75 &nbsp;<strong>← conflict</strong></td></tr>
<tr><td><code>fatal</code></td>
    <td><span class="swatch" style="background:#FF3B30"></span>system <code>.red</code><br><code>xmark.circle</code></td>
    <td class="note">not representable — the toast enum has no <code>fatal</code></td>
    <td><span class="swatch" style="background:#FF8A75"></span><strong>danger</strong> — #FF8A75 on #321914, border #C55646<br><code>xmark.circle</code></td></tr>
</table>
<p class="note"><strong>Conflict 1</strong> — <code>degradation</code> rendered yellow on the
full-screen surfaces and red in toasts. Resolved: both read <code>warning</code>.
<strong>Conflict 2</strong> — the banner ignored severity entirely. Resolved: it derives tone
like every other surface, which is what produced the blue banners above.</p>

{''.join(blocks)}

<h2>VoiceOver — the declared labels, before and after</h2>
<p class="note"><strong>Every identifier is unchanged</strong> across four component renames, which
is the point of pinning them. <code>diff before/a11y.txt after/a11y.txt</code> shows exactly one
change, and it is DS.3a's: <em>&ldquo;No audio detected.&rdquo;</em> moves from <em>&ldquo;Alert:
&hellip;&rdquo;</em> to <em>&ldquo;Critical: &hellip;&rdquo;</em>, and the <code>degradation</code> row
now demonstrates a dropped stem, which is what that severity actually means. These are the labels
each surface <em>declares</em>; VoiceOver applies its own rotor and punctuation on top.</p>
{a11y_table("docs/reviews/DS.3/after/a11y.txt")}

<h2>What to look at</h2>
<ol>
  <li><strong>The blue banners.</strong> Amber → blue on the only banner states a user reaches.
      Correct per the severity map, and a bigger change than the increment predicted.</li>
  <li><strong>The silence toast.</strong> Red before, red after — but for a different reason, and it
      now speaks as &ldquo;Critical&rdquo;. The yellow one is a genuine degradation: a dropped stem.</li>
  <li><strong>The blocking screen.</strong> System red/orange/yellow → the token triples. Layout,
      copy, buttons and keyboard default action unchanged.</li>
</ol>
"""
open("docs/reviews/DS.3/index.html", "w").write(html)
print("index.html written")
