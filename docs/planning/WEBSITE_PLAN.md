# Website Plan — Uzume (formerly Phosphene)

*2026-08-09 · Public-beta website: promotion + education for users and contributors*

> **Frozen RN.0 snapshot — not maintained here.** The live version of this document is owned by the
> brand repository [`hoaxpoet/uzume-site`](https://github.com/hoaxpoet/uzume-site) (`docs/planning/`).
> This copy exists as the rename's preserved evidence (RN.0) and is deliberately left as written.
> RN.3 reconciled the two: the site's copies now carry this copy's registrar-corrected domain facts,
> and this copy is not updated again. Read the site's version for anything current. (D-228)

> The name is decided: **Uzume** (see NAMING_REPORT.md §Final Decision). References to "Phosphene" below mean the current app repo, pre-rename.

## 1. Decisions locked

The name is **Uzume** (oo-ZOO-meh); the domain is **uzume.io** (canonical — registrar-confirmed available at ~$50/yr, 2026-08-12), with watch/backorders on **uzume.app** (registered, parked — parked domains lapse) and **uzume.com** (held by an active taiko ensemble; expiry 2026-08-27, likely renews). The get* variants were available and deliberately declined. Scope at launch is a **marketing landing page, a docs section, and a preset gallery** (blog deferred). Stack is **Astro 7 with Starlight** for the docs section. Hosting is **Cloudflare** (git-connected builds, preview deploys, free static serving with no bandwidth cap), domain via **Cloudflare Registrar**. The site lives in a **separate repo** from the app. A **brand/design-token workstream** is explicit, since no logo, wordmark, or capture footage exists yet — and the name hands the brand its imagery: the Iwato story (a dark world, a planned performance, a mirror catching first light), dawn colors over near-black, rhythm. Brand-system names settled with it: **Pythagoras** is the in-app onboarding/help persona, **Omoikane** the orchestrator's internal codename, and the tagline is Coleridge's public-domain line — *"a light in sound, a sound-like power in light."*

One platform note from current research: Cloudflare now steers new projects toward **Workers with static assets** rather than classic Pages — Pages remains fully supported, but Workers is the invested-in path and has feature parity on everything this site needs (git-connected builds via Workers Builds, preview URLs on by default, custom domains, `_headers`/`_redirects`, free static asset requests). Recommendation: create the project as a Worker with static assets. If any rough edge appears, the same `dist/` output deploys to Pages unchanged.

## 2. Audiences and jobs

The site serves two audiences with different jobs, and the IA keeps them separate after a shared front door.

**Listeners** need to understand what Phosphene is in ten seconds (it performs visuals to whatever you're playing; it does not control playback), see it moving (footage is the argument — no static screenshot can make the case), know whether their machine qualifies (Apple Silicon, macOS 14+), and get it installed without fear (the Screen Recording permission for system-audio capture is the single scariest moment in onboarding; the site must explain it before the OS dialog does — audio-only capture, nothing else, and local-file playback needs no permission at all).

**Contributors** need to learn that presets are the contribution surface (a two-file Metal + JSON drop-in), see that the path is real (hot-reload loop, `swift test` gates, no accounts or hardware needed), and be routed into the repo's existing contributor docs, which are already strong.

Public-beta framing throughout: free, in beta, feedback wanted — with GitHub Issues as the single feedback channel.

## 3. Information architecture

```
/              Landing
/gallery       Certified-preset showcase
/docs/…        Starlight docs section
/download      Get the beta
/credits       ML weights + Milkdrop-inspired attribution (mirrors docs/CREDITS.md)
```

**Landing (`/`).** Full-bleed hero of capture footage (muted, `prefers-reduced-motion`-respecting, poster fallback), one line of what it is, download CTA with the requirements right there. Then three beats that differentiate it from every winamp-descendant visualizer: it *pre-analyzes* the whole playlist (stem separation + MIR) before a note plays; an *AI orchestrator plans the session* — which visual accompanies which track, where transitions land, the emotional arc; and *live analysis refines the plan* as the music actually unfolds. Then a gallery teaser strip, a contributor call-to-action ("the visualizers are the contribution — write one shader, see it live-reload"), a short FAQ (does it control my music? no — you play, it listens; why Screen Recording permission; does it work without Spotify? yes, local files), and a footer (GitHub, MIT license, credits).

**Gallery (`/gallery`).** A grid of certified presets, each a looping muted clip (lazy-loaded, playing only in viewport) with name, author, and `inspired_by` attribution where present. This page is the strongest marketing asset the project can have and doubles as the contributor trophy case — a merged preset means your work on the site with your name on it, which is worth more than any "please contribute" copy. Entries are a content collection with a schema (name, author, certified date, attribution block, clip/poster paths) — deliberately congruent with the preset sidecar JSON, so a script can generate gallery entries from the repo's own sidecars and CREDITS.md rather than hand-maintaining them.

**Docs (`/docs`).** Starlight. Curated for the web, not a mirror of the repo — the repo docs are written maintainers-first (increment IDs, D-### decisions, M7) and remain canonical; the site carries the outsider-facing subset, rewritten where needed: Getting Started (requirements, install, first run, the permission explainer, local files vs. streaming), Using Phosphene (Spotify connector setup, troubleshooting the silent-tap gotcha), and Contributing Presets (what a preset is, the hot-reload loop, your-first-preset walkthrough, the gates and certification lifecycle, Milkdrop-porting posture). Each page carries frontmatter naming its upstream repo doc; CI link-checks upstream references so drift gets caught. Start with manual curation — the web versions need rewriting anyway — and revisit script-driven sync only if drift becomes a real cost.

**Download (`/download`).** Points at GitHub Releases as the artifact host (free bandwidth, versioned, no extra infra); install steps; Gatekeeper/notarization note; beta expectations; requirements repeated. **Hard dependency flagged:** the repo today is clone-and-build. A public beta needs a signed, notarized `.dmg` or `.zip` on GitHub Releases — Apple Developer Program ($99/yr), Developer ID signing, `notarytool` in the release pipeline. That work lives in the app repo, not the site repo, but the site's central CTA is blocked without it. It belongs at the top of the pre-launch checklist.

## 4. Brand and design system

The governing principle: **the engine's output is the brand.** The design system's job is to build a restrained, dark, typographic frame and then get out of the way — footage provides all the color. That makes this a deliberately small system, which is what makes it achievable as a solo workstream.

Concretely: a near-black canvas, a neutral text ramp, exactly one accent color, one display face + one text face (system/variable fonts to keep the site at zero webfont cost, or a single variable font if the wordmark wants it), a spacing/radius scale, and two or three motion durations. All of it lives as CSS custom properties in a single `tokens.css` that both the landing pages and Starlight consume — Starlight themes via CSS custom properties, so the docs inherit the identity for free rather than being a differently-skinned annex.

Site components (`.astro`, zero-JS by default): `Nav`, `Footer`, `Button`, `VideoTile` (poster + lazy loop + reduced-motion fallback), `Callout`, `RequirementsList`, `PresetCard`. A `/design` page documents tokens and components with live examples — cheap to build with the same content machinery, and it keeps the system honest as the site grows.

Two identity notes. The wordmark + app icon need creating (nothing exists); a type-only wordmark over engine footage is a strong, low-cost direction consistent with "output is the brand." And the site should *visibly honor* `prefers-reduced-motion` and mention the app's flash-safety certification gate — photosensitivity care is already engineering reality in this project (0 flashes/s harness for certified presets); saying so on the site is both an accessibility obligation and a credibility signal no competitor in this space bothers with.

## 5. Capture and media pipeline

The assets don't exist yet, so this is a real workstream, not an afterthought.

**Capture.** Per certified preset: a 15–30 s loop at 1080p60, captured against music that shows the preset's musical role (the sidecar's audio routes tell you what to feature). Plus one 30–60 s hero reel cutting across presets for the landing page. **Licensing constraint that must be decided early:** even muted clips of visuals *derived from* commercial tracks are safest captured against music you have rights to — use openly-licensed or self-produced tracks for all published captures, and note the track + license per clip in the asset manifest. (The repo already thinks this way about fixtures; extend the discipline to marketing captures.)

**Encode.** `ffmpeg` ladder per clip: AV1/WebM primary + H.264/MP4 fallback, muted (no audio track at all — smaller and sidesteps licensing), AVIF/JPEG poster. Budget ≈ 8–12 MB per gallery loop, hero somewhat larger. A small `Scripts/encode_captures.sh` in the site repo makes this reproducible.

**Storage.** Videos in git are misery. Put all media in a **Cloudflare R2 bucket** from day one, served on `media.<domain>` — zero egress fees, 10 GB free storage (a full gallery fits comfortably), and the site repo stays a few megabytes forever. The site references media by URL; an asset manifest (JSON in the site repo) is the source of truth for what exists, its poster, and its music-license note.

## 6. Repo and development pipeline

**Repo:** `hoaxpoet/uzume-site` (note: the bare GitHub username `uzume` is held by a near-inactive third-party account, so an exact-name org isn't available — staying under `hoaxpoet` sidesteps it), structure roughly:

```
src/
  components/      .astro components
  content/
    presets/       gallery collection (one file per preset)
    docs/          Starlight content
  pages/           landing, gallery, download, credits, design
  styles/tokens.css
public/            favicons, og images, _headers, _redirects
Scripts/           encode_captures.sh, sync helpers
```

**Toolchain:** Node LTS pinned (`.nvmrc` — same pinning discipline as `.xcode-version`), npm, Prettier, `astro check` for type/content-schema validation. Astro 7 / Starlight ≥ 0.41 (current as of mid-2026).

**CI (GitHub Actions):** on every PR — install, `astro check`, build, `lychee` link check (internal links + the upstream repo-doc references from docs frontmatter). Optional later: Lighthouse CI with a performance budget, which matters on a video-heavy site.

**Deploys:** Cloudflare's git integration builds on push — `main` → production, every PR → its own preview URL. That preview URL is the site's equivalent of the app repo's M7 review: visual work gets judged rendered, not in diff form. Rollback is a one-click redeploy of a previous build in the Cloudflare dashboard, or `git revert`.

**Working style:** the site repo gets its own lightweight `CLAUDE.md` (stack, tokens-first rule, content-collection schemas, "media lives in R2, never in git," encode budgets). The app repo's increment discipline can carry over in spirit — small PRs, preview-reviewed — without the full ceremony; a website doesn't need DECISIONS.md-grade process, and importing it would be overhead without payoff.

## 7. Hosting and domain setup (one-time checklist)

1. ~~Decide the name~~ — done: Uzume.
2. Register **uzume.io** (~$50/yr; free WHOIS redaction; auto-renew on) — the canonical domain. In the same session, place watch/backorders on **uzume.app** (registered/parked as of 2026-08-12) and **uzume.com** (expires 2026-08-27; the active owner will likely renew, but the watch is nearly free).
3. Create the GitHub repo; scaffold (`npm create astro@latest`, add Starlight integration); commit.
4. Cloudflare dashboard → Workers & Pages → create → connect the GitHub repo. Build: `npm run build`, assets dir `dist/`. Confirm the preview-URL-per-PR behavior on a test PR.
5. Attach the custom domain (DNS is already in-house since the registrar is Cloudflare); add `www` → apex redirect; set security headers in `public/_headers` (CSP, `X-Content-Type-Options`, referrer policy).
6. Create the R2 bucket, enable public access via `media.<domain>` custom domain.
7. Enable Cloudflare Web Analytics (free, cookieless, no consent banner needed) — or skip analytics entirely; both are defensible for an OSS project. Decide once, at setup.

## 8. Phases

**Phase 0 — Foundation (≈ a day; unblocked now).** Steps 2–7 above, ending with a "hello world" Astro site live at uzume.io with PR previews working. The pipeline exists before any real page does.

**Phase 1 — Design system + landing (2–3 working sessions).** `tokens.css`, core components, `/design` page, then the landing page built from them, using placeholder capture footage (any preset, rough capture) so layout work isn't blocked on final assets. Ship it — a good landing page alone is a legitimate public site.

**Phase 2 — Capture pipeline + gallery (2–4 sessions, partly app-side).** Settle the capture-music licensing decision, capture and encode clips for certified presets, stand up R2, build the gallery collection + pages, re-cut the hero with real footage.

**Phase 3 — Docs (2–3 sessions).** Curate the outsider-facing docs into Starlight: getting started, permission explainer, using-with-streaming, contributing-presets path. Wire the upstream-reference link checking.

**Phase 4 — Launch polish (1–2 sessions).** OG/social images (a frame from the hero reel per page), favicons/app-icon derivation, 404 page, sitemap + basic SEO pass, `prefers-reduced-motion` audit, Lighthouse pass on throttled mobile, and the launch checklist below.

**Launch gate (site-external dependencies):** signed + notarized beta build on GitHub Releases; at least ~6–8 certified presets captured for a gallery that looks alive; the Phosphene → Uzume rename propagated through the app repo (RN.1 session prompt exists in prompts/; mechanical checklist also in NAMING_REPORT.md).

## 9. Costs

| Item | Cost |
|---|---|
| Domain (1–3 TLDs, Cloudflare at-cost) | ~$10–40/yr |
| Hosting (Cloudflare Workers static assets, free tier) | $0 |
| Media (R2, ~≤10 GB, zero egress) | $0 |
| Analytics (Cloudflare Web Analytics) | $0 |
| CI (GitHub Actions, public repo) | $0 |
| *(App-side, pre-existing need)* Apple Developer Program for notarized beta | $99/yr |

Steady state: the website itself costs the price of the domain.

## 10. Open questions

~~The name~~ — decided: Uzume. Remaining: the **capture-music licensing** posture (openly-licensed vs. self-produced tracks for published footage). The **beta distribution** timeline (notarized Releases artifact — app-repo work that gates the download page). **Analytics** yes/no. The **app-repo rename timing** (before the site goes live, ideally in one dedicated increment). And whether `/credits` should also surface preset-contributor profiles (name + link per certified preset) from day one — cheap to do via the gallery collection, and a strong contributor incentive.
