# Session prompt — BRAND.1

## Increment BRAND.1 — Uzume brand foundations (pre-RN.1)

**Type:** brand/design (new-repo work; zero app-repo code changes). Runs with the **Impeccable** design plugin — `/impeccable <command>` — which is installed and symlinked in this environment.

**Objective.** After this session, the Uzume brand exists as usable artifacts, not intentions: an Impeccable-format brief (PRODUCT.md + DESIGN.md) that encodes the brand so every future design session inherits it; a design-token file (`tokens.css`); a wordmark (SVG, light-on-dark primary); a macOS app icon (1024 master + full `.iconset`); a self-contained design-foundations page presenting all of it; and a short BRAND.md recording story, voice, and usage rules. This unblocks RN.1 (the app rename ships with a real icon and name treatment, not a stale brand) and pre-loads Phase 1 of the website plan (the site inherits `tokens.css` unchanged).

Everything is grounded in decisions already made (see read-first list): the name is Uzume (oo-ZOO-meh); the identity principle is **"the engine's output is the brand"** — a restrained, dark, typographic frame that lets footage provide the color; the brand story is the Ama-no-Iwato myth (a dark world, a *planned* performance, a mirror catching first light); the tagline is Coleridge's public-domain line, *"a light in sound, a sound-like power in light"*; the in-app persona is Pythagoras; the orchestrator codename is Omoikane.

## Skill invocations

- `/impeccable shape` after the brief is written, before any pixel work (Task 3).
- `/impeccable critique` + `/impeccable audit` after the build (Task 7); focused passes (`/impeccable typeset`, `/impeccable colorize`, `/impeccable layout`) only where critique demands them.
- `/impeccable polish` as the final pass (Task 8).
- Impeccable's own doctrine governs iteration: **"the brief wins"** (Task 1's brief outranks any later aesthetic impulse — including Impeccable's defaults), and **verify in bounded passes** (one batched inspection round, one fix batch, at most one confirm round — no polish spirals; this is the M7 discipline in design clothing).
- `closeout` at the end (mandatory), adapted: this repo has no `closeout_evidence.sh`, so §2 evidence is the verification-command outputs plus the artifact inventory (Task 9).

## Read-first file list

1. `docs/planning/NAMING_REPORT.md` — §Final Decision: the name, pronunciation, sensitivity posture, neighbors.
2. `docs/planning/MYTH_RESEARCH.md` — the Iwato retelling (the brand story verbatim) and the copy vault (Coleridge line, aurora-that-listens, House of the Sun).
3. `docs/planning/WEBSITE_PLAN.md` — §4 Brand and design system (the governing restraint principle, token scope, photosensitivity stance) and §3 IA (what the tokens must eventually serve).
4. Impeccable's PRODUCT.md / DESIGN.md conventions (plugin docs) — the brief format Task 1 fills.

## Pre-flight invariants

- **uzume.io is registered** (Matt's confirmation in chat is the check; uzume.app and uzume.com are third-party, on watch/backorder). Not registered → stop; brand assets must not exist for an unowned name.
- Working repo `uzume-site` exists locally (fresh `git init` is fine; remote optional this session), with the three planning docs copied to `docs/planning/`. Source copies live in the phosphene project at `phosphene/planning/` (NAMING_REPORT.md, MYTH_RESEARCH.md, WEBSITE_PLAN.md — placed there 2026-08-09, untracked). Missing docs → stop and ask.
- `/impeccable` resolves (plugin loaded). If not → stop; this increment is defined around it.
- No work targets the phosphene app repo. If a task seems to need an app-repo edit, that's a finding for RN.1, not an action.

## Numbered tasks

1. **Write the brief (PRODUCT.md + DESIGN.md), from the planning docs, before any design.** PRODUCT.md: audience (two: listeners who want their music made visible; shader-writing contributors), lane (native macOS, free public beta, open source), voice (see Task 6). DESIGN.md: the restraint principle stated as law — near-black canvas, neutral text ramp, **exactly one accent**, footage is the only saturation source; anti-references named explicitly (no vaporwave/synthwave neon kitsch, no DAW-plugin skeuomorphism, no crypto-glow gradients, no generic "AI shimmer"); typography direction (one display face, one text face, open-licensed, embeddable); motion doctrine (motion belongs to the engine — the chrome around it stays nearly still; `prefers-reduced-motion` is honored absolutely, and the brand *says so* — photosensitivity care is already engineering fact in this product, certified presets measure 0 flashes/s; the brand claims that virtue explicitly). **Done-when:** both files exist and a cold read of them alone would reproduce the intended brand within squinting distance.

2. **Design tokens (`tokens.css`).** CSS custom properties only, no framework: canvas + surface steps, text ramp, the single accent (plus its hover/dim states), type scale, spacing scale, radii, three motion durations with a reduced-motion collapse. Every text/background pair used by the design page must pass WCAG AA — verify programmatically (Task 9), not by eye. **Done-when:** `tokens.css` exists; a token-only swatch section renders on the design page; contrast script passes.

3. **`/impeccable shape` the exploration, then build three wordmark directions.** Type-only or near-type-only "Uzume" treatments (per the DECISION-NEEDED, all three motif directions), each as clean SVG with real vector letterforms (no raster text), light-on-dark primary; include a pronunciation lockup variant (small "oo-ZOO-meh" beside or beneath the mark) for site/About use. **Done-when:** three distinct SVGs render crisply at 32 px and 512 px wide; each carries a one-paragraph rationale in BRAND.md's working notes.

4. **App icon comps, one per wordmark direction.** macOS-native discipline: the current squircle canvas, legible at 16 px, no text in the icon, dark field consistent with the tokens. The myth enters *abstractly* — see Do-NOT for the hard line. **Done-when:** three 1024 px masters exist and each has been actually viewed at 16/32/128 px (screenshots in the working notes, not assumptions).

5. **HARD STOP — Matt's visual review (M7 for the brand).** Assemble a single review page: the three directions side by side — wordmark, icon at three sizes, accent applied to a sample button/card, each with its rationale. Present, **stop, and report**. Do not proceed to Task 6 until Matt picks a direction (or redirects). This session's remaining tasks resume on his pick.

6. **Finalize the chosen direction + BRAND.md.** Final wordmark SVG (+ pronunciation lockup), final icon master + generated `.iconset`/`.icns`, favicon derivatives (SVG + 32/180 px). BRAND.md: the Iwato story in one tellable paragraph; the tagline and its attribution; voice — plain, warm, unhurried, never breathless (see UX_SPEC copy principles for register); the Pythagoras persona defined in two sentences as *future* app-UX material (named here, not written here); pronunciation; usage rules (clear space, minimum sizes, don't-recolor, don't-set-on-photography); the accent's single-accent law. **Done-when:** all assets exist at final paths; BRAND.md reads as something a stranger could apply.

7. **Design-foundations page (`design/index.html`).** Self-contained (inline CSS reading from `tokens.css`, no build step, no JS beyond a reduced-motion demo toggle): tokens, type specimens, wordmark usage, icon, spacing/radius scale, do/don't pairs. This page is the design system's documentation and its first consumer. Then `/impeccable critique` and `/impeccable audit` it; fix in one batch; at most one confirm round. **Done-when:** the page passes critique/audit with findings addressed; it renders correctly with `prefers-reduced-motion` enabled.

8. **`/impeccable polish`, then freeze.** One polish pass across page + assets. No further iteration after it — bounded-pass doctrine. **Done-when:** polish findings are applied or explicitly waived with a reason.

9. **Verification + inventory, then stop.** Run the verification checks below; produce the artifact inventory (path → purpose → format → license of any font used); closeout per the adapted format. No pushes anywhere without Matt's explicit "yes, push."

## Do NOT

- Do **not** depict Ame-no-Uzume herself, shrine iconography, torii, shimenawa, or any Shinto ritual object in the wordmark or icon. The sensitivity posture (NAMING_REPORT §Final Decision) holds *because* the reference stays abstract — light, mirror-catch, rhythm, the crack of dawn at a dark door. Literal religious imagery converts homage into costume; it is the one way to lose the name's goodwill.
- Do **not** touch the phosphene app repo, the RN.1 prompt, or anything RN.1 owns (bundle IDs, Info.plist, in-app strings). The icon *file* is produced here; RN.1 installs it.
- Do **not** write Pythagoras persona copy beyond the two-sentence definition — persona UX is its own future increment.
- Do **not** introduce a second accent color, gradients as identity, or any motion in brand chrome beyond the tokened durations. The engine is the show; the brand is the theater, dark and quiet.
- Do **not** use unlicensed or embed-restricted fonts, stock imagery, or any raster asset you did not generate this session. Open licenses only (OFL or equivalent), recorded in the inventory.
- Do **not** polish past the bounded passes. If direction feels wrong at Task 7, that is a Task 5 conversation with Matt, not a solo redesign.

## Verification commands

No app-repo battery applies (no Swift/Metal touched). This increment's gates:

```
# SVG validity + no embedded rasters in wordmark files
python3 -c "import xml.dom.minidom,glob,sys; [xml.dom.minidom.parse(f) for f in glob.glob('brand/*.svg')]"
grep -L "data:image" brand/*.svg   # every SVG must appear (i.e., none embed rasters)

# Contrast: every token text/background pair ≥ WCAG AA (script written in Task 2)
python3 Scripts/check_contrast.py tokens.css

# Icon set completeness
iconutil -c icns brand/icon/Uzume.iconset -o /tmp/Uzume.icns && echo ICONSET-OK

# Design page opens and honors reduced motion (manual, screenshot both states)
open design/index.html
```

Plus: `/impeccable audit` output attached; 16/32/128 px icon screenshots attached; the Task-5 review page archived under `docs/reviews/BRAND.1/`.

## Commit message templates

Small commits, local-only until Matt's explicit "yes, push":

```
[BRAND.1] Brief: PRODUCT.md + DESIGN.md (the brief wins)
[BRAND.1] Tokens: tokens.css + contrast gate
[BRAND.1] Wordmark: three directions for M7 review
[BRAND.1] Icon: three masters + size-legibility screenshots
[BRAND.1] Final: chosen direction — wordmark, iconset, favicons, BRAND.md
[BRAND.1] Design page: foundations + critique/audit fixes
```

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verification outputs + artifact inventory standing in as §2 evidence (no `closeout_evidence.sh` in this repo — note the substitution explicitly). Increment-specific additions: (1) Matt's Task-5 direction pick, quoted; (2) the critique/audit findings table with fixed/waived status; (3) font license records; (4) a one-line handoff note to RN.1 ("icon master at `brand/icon/…`, install during RN.1 Task 3").

## DECISION-NEEDED

**Question:** How literal should the icon and wordmark's myth reference be?

- **Option A — the crack of light (recommended).** Pure abstraction: a dark field broken by one thin line or wedge of dawn-colored light, as if a door just opened. What you'd see: the quietest, most timeless mark; reads as "light in darkness" even to someone who never hears the myth; scales flawlessly to 16 px.
- **Option B — the mirror-catch.** A dark disc holding a single off-center gleam — the mirror at the cave, the instant it catches her radiance. What you'd see: warmer and more object-like, a jewel-in-the-dock quality; carries a hint of lens/eye, appropriate for a visualizer.
- **Option C — the rhythm.** A minimal mark built from repeated vertical strokes with one stroke lit — the drummed beat with light arriving on it. What you'd see: the most "music software" of the three, closest kin to a waveform, and the most at risk of reading generic.

**Recommendation:** Option A, with B's warmth borrowed for the accent color (first-light amber over near-black).

**Default-if-no-reply:** develop all three through Task 4 regardless (the session does this anyway); at the Task-5 stop, if Matt gives no direction within the session, park the session — the hard stop is real; finalization without his pick is not an option.
